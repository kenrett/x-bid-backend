require "test_helper"
require "ostruct"

class RefundIdempotencyAcrossPathsTest < ActiveSupport::TestCase
  class FakeStripeEvent
    attr_reader :id, :type, :data

    def initialize(payload)
      @id = payload[:id]
      @type = payload[:type]
      @payload = payload
      @data = OpenStruct.new(object: payload[:data][:object])
    end

    def to_hash
      @payload
    end
  end

  setup do
    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)

    result = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_1",
      stripe_payment_intent_id: "pi_1",
      stripe_event_id: "evt_purchase_1",
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      source: "test"
    )
    assert result.ok?
    @purchase = result.purchase
    assert_equal 10, @user.reload.bid_credits
  end

  test "admin issues refund then webhook arrives: no double MoneyEvent or credit reversal" do
    response = ::Payments::Gateway::GatewayResponse.new(success?: true, refund_id: "re_1", raw_response: { id: "re_1" })

    admin_result = ::Payments::Gateway.stub(:issue_refund, ->(**_) { response }) do
      Admin::Payments::IssueRefund.new(actor: @admin, payment: @purchase, amount_cents: @purchase.amount_cents, reason: "full").call
    end
    assert admin_result.ok?
    assert_equal "refunded", @purchase.reload.status
    assert_equal 0, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_1").count
    assert_equal 1, CreditTransaction.where(purchase_id: @purchase.id, reason: "purchase_refund_credit_reversal").count

    refund_payload = {
      id: "evt_refund_webhook_1",
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_1",
          payment_intent: "pi_1",
          amount_refunded: @purchase.amount_cents,
          refunds: { data: [ { id: "re_1" } ] }
        }
      }
    }

    webhook_result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    assert webhook_result.ok?

    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_1").count
    assert_equal 1, CreditTransaction.where(purchase_id: @purchase.id, reason: "purchase_refund_credit_reversal").count
    assert_equal 0, @user.reload.bid_credits
  end

  test "webhook arrives first then admin attempts refund: gateway not called and no double reversal" do
    refund_payload = {
      id: "evt_refund_webhook_2",
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_2",
          payment_intent: "pi_1",
          amount_refunded: @purchase.amount_cents,
          refunds: { data: [ { id: "re_2" } ] }
        }
      }
    }

    webhook_result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    assert webhook_result.ok?
    assert_equal "refunded", @purchase.reload.status
    assert_equal 0, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_1").count
    assert_equal 1, CreditTransaction.where(purchase_id: @purchase.id, reason: "purchase_refund_credit_reversal").count

    gateway = Class.new do
      def self.issue_refund(**)
        raise "should not be called"
      end
    end

    admin_result = Admin::Payments::IssueRefund.new(actor: @admin, payment: @purchase, amount_cents: @purchase.amount_cents, reason: "full", gateway: gateway).call
    assert admin_result.ok?
    assert_equal :already_refunded, admin_result.code

    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_1").count
    assert_equal 1, CreditTransaction.where(purchase_id: @purchase.id, reason: "purchase_refund_credit_reversal").count
    assert_equal 0, @user.reload.bid_credits
  end
end
