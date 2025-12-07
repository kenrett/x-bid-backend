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
  end

  test "fails when gateway declines" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: false, error_code: "card_error", error_message: "declined")

    result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @payment, amount_cents: 200).call
    end

    refute result.ok?
    assert_equal :gateway_error, result.code
    assert_equal 0, @payment.reload.refunded_cents
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
end
