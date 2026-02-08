require "test_helper"

class AdminPaymentsIssueRefundTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)
    @payment = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      stripe_checkout_session_id: "cs_123",
      stripe_payment_intent_id: "pi_123",
      status: "applied"
    )

    Credits::Apply.apply!(
      user: @user,
      reason: "bid_pack_purchase",
      amount: @bid_pack.bids,
      idempotency_key: "purchase:#{@payment.id}:grant",
      kind: :grant,
      purchase: @payment,
      stripe_payment_intent_id: @payment.stripe_payment_intent_id,
      stripe_checkout_session_id: @payment.stripe_checkout_session_id,
      metadata: { source: "test" }
    )
    assert_equal 10, @user.reload.bid_credits
  end

  test "issues a full refund and logs" do
    logged = []
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_123", raw_response: { id: "re_123" })

    result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
      ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
        Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: @payment.amount_cents, reason: "duplicate").call
      end
    end

    assert result.ok?
    assert_equal "refunded", @payment.reload.status
    assert_equal @payment.amount_cents, @payment.refunded_cents
    assert_equal "re_123", @payment.refund_id
    assert_equal 0, @user.reload.bid_credits
    assert_equal 1, CreditTransaction.where(purchase_id: @payment.id, reason: "purchase_refund_credit_reversal").count
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal true, logged.last[:success]
    assert_equal "admin.payments.issue_refund", logged.last[:event]
    assert_equal "duplicate", logged.last[:reason]
  end

  test "partial refund marks payment partially_refunded" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_partial", raw_response: { id: "re_partial" })

    result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial").call
    end

    assert result.ok?
    assert_equal "partially_refunded", @payment.reload.status
    assert_equal 100, @payment.refunded_cents
    assert_equal "re_partial", @payment.refund_id
    assert_equal 9, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
  end

  test "full_refund=true refunds remaining refundable cents when amount is omitted" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_full", raw_response: { id: "re_full" })

    result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, full_refund: true, reason: "full").call
    end

    assert result.ok?
    assert_equal "refunded", @payment.reload.status
    assert_equal @payment.amount_cents, @payment.refunded_cents
  end

  test "fails when amount is omitted and full_refund is false" do
    gateway = Class.new do
      def self.issue_refund(**)
        raise "should not be called"
      end
    end

    result = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, gateway: gateway).call

    refute result.ok?
    assert_equal :invalid_amount, result.code
    assert_equal "applied", @payment.reload.status
  end

  test "fails when gateway declines" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: false, error_code: "card_error", error_message: "declined")

    result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 200).call
    end

    refute result.ok?
    assert_equal :gateway_error, result.code
    assert_equal 0, @payment.reload.refunded_cents
    assert_equal 10, @user.reload.bid_credits
    assert_equal 0, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
  end

  test "non-admin actors are forbidden" do
    result = Admin::Payments::IssueRefund.new(actor: @user, payment: @payment, amount_cents: 200).call

    refute result.ok?
    assert_equal :forbidden, result.code
    assert_equal 0, @payment.reload.refunded_cents
  end

  test "rejects already refunded payments" do
    @payment.update!(refunded_cents: @payment.amount_cents, status: "refunded")

    gateway = Class.new do
      def self.issue_refund(**)
        raise "should not be called"
      end
    end

    result = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, gateway: gateway).call

    assert result.ok?
    assert_equal :already_refunded, result.code
  end

  test "already-refunded is idempotent" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_abc", raw_response: { id: "re_abc" })
    calls = 0
    gateway = Class.new do
      class << self
        attr_accessor :calls, :response
      end

      def self.issue_refund(**)
        self.calls += 1
        response
      end
    end
    gateway.calls = calls
    gateway.response = response

    first = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial", gateway: gateway).call
    assert first.ok?
    credits_after_first = @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, CreditTransaction.where(purchase_id: @payment.id, reason: "purchase_refund_credit_reversal").count

    second = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 50, reason: "more", gateway: gateway).call

    assert second.ok?
    assert_equal :already_refunded, second.code
    assert_equal 1, gateway.calls
    assert_equal credits_after_first, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, CreditTransaction.where(purchase_id: @payment.id, reason: "purchase_refund_credit_reversal").count
  end

  test "partial refund already exists and exceeding remaining is rejected" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_partial", raw_response: { id: "re_partial" })
    gateway = Class.new do
      class << self
        attr_accessor :response
      end

      def self.issue_refund(**)
        response
      end
    end
    gateway.response = response

    first = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial", gateway: gateway).call
    assert first.ok?
    assert_equal 100, @payment.reload.refunded_cents

    rejecting_gateway = Class.new do
      def self.issue_refund(**)
        raise "should not be called"
      end
    end

    result = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: @payment.amount_cents, gateway: rejecting_gateway).call

    refute result.ok?
    assert_equal :amount_exceeds_charge, result.code
  end

  test "spent credits policy blocks refund" do
    Credits::Debit.for_bid!(user: @user, auction: Auction.create!(title: "A", description: "d", start_date: 1.day.ago, end_time: 1.day.from_now, current_price: 1.0, status: :active), idempotency_key: "spend-1", locked: false)
    Credits::Debit.for_bid!(user: @user, auction: Auction.last, idempotency_key: "spend-2", locked: false)
    Credits::Debit.for_bid!(user: @user, auction: Auction.last, idempotency_key: "spend-3", locked: false)
    assert_equal 7, @user.reload.bid_credits

    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_big", raw_response: { id: "re_big" })
    result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: @payment.amount_cents, reason: "full").call
    end

    refute result.ok?
    assert_equal :cannot_refund_spent_credits, result.code
    assert_equal 0, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
  end

  test "concurrent refund requests only call gateway once" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_concurrent", raw_response: { id: "re_concurrent" })

    calls = 0
    calls_lock = Mutex.new
    gateway = Class.new do
      class << self
        attr_accessor :calls, :calls_lock, :response
      end

      def self.issue_refund(**)
        calls_lock.synchronize { self.calls += 1 }
        response
      end
    end
    gateway.calls = calls
    gateway.calls_lock = calls_lock
    gateway.response = response
    queue = Queue.new
    results = []

    threads = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          queue.pop
          results << Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial", gateway: gateway).call
        end
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          queue.pop
          results << Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial", gateway: gateway).call
        end
      end
    ]

    sleep 0.1
    queue.close
    threads.each(&:join)

    assert results.all?(&:ok?)
    assert_equal 1, gateway.calls
  end
end
