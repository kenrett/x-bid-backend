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
      status: "completed"
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

    result = Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100).call

    refute result.ok?
    assert_equal :already_refunded, result.code
  end

  test "already-refunded is idempotent" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_abc", raw_response: { id: "re_abc" })

    first = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 100, reason: "partial").call
    end
    assert first.ok?
    credits_after_first = @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, CreditTransaction.where(purchase_id: @payment.id, reason: "purchase_refund_credit_reversal").count

    second = ::Payments::Gateway.stub(:issue_refund, ->(**_) { raise "should not be called" }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 50, reason: "more").call
    end

    refute second.ok?
    assert_equal :already_refunded, second.code
    assert_equal credits_after_first, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, CreditTransaction.where(purchase_id: @payment.id, reason: "purchase_refund_credit_reversal").count
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
end
