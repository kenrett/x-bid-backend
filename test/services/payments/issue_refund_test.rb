require "test_helper"

class PaymentsIssueRefundTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "buyer@example.com", password: "password", role: :user)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 5.0, active: true)
    @purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 500,
      currency: "usd",
      status: "completed",
      stripe_payment_intent_id: "pi_123"
    )
  end

  test "refund amount cannot exceed original purchase" do
    gateway = Class.new do
      def self.issue_refund(**)
        raise "should not be called"
      end
    end

    result = Payments::IssueRefund.new(purchase: @purchase, amount_cents: 600, gateway: gateway).call
    refute result.ok?
    assert_equal :amount_exceeds_charge, result.code
    assert_equal 0, MoneyEvent.where(event_type: :refund).count
  end

  test "duplicate refunds are rejected" do
    gateway = Class.new do
      def self.issue_refund(**)
        Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_1", raw_response: {})
      end
    end

    first = Payments::IssueRefund.new(purchase: @purchase, amount_cents: 100, gateway: gateway).call
    assert first.ok?
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count

    second = Payments::IssueRefund.new(purchase: @purchase, amount_cents: 100, gateway: gateway).call
    refute second.ok?
    assert_equal :already_refunded, second.code
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
  end
end
