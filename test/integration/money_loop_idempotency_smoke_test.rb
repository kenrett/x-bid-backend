require "test_helper"
require "ostruct"

class MoneyLoopIdempotencySmokeTest < ActiveSupport::TestCase
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
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)
  end

  test "purchase and refund are idempotent across duplicate calls" do
    apply1 = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_smoke",
      stripe_payment_intent_id: "pi_smoke",
      stripe_event_id: "evt_purchase_smoke",
      amount_cents: 999,
      currency: "usd",
      source: "test_smoke"
    )
    assert apply1.ok?

    apply2 = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_smoke",
      stripe_payment_intent_id: "pi_smoke",
      stripe_event_id: "evt_purchase_smoke",
      amount_cents: 999,
      currency: "usd",
      source: "test_smoke"
    )
    assert apply2.ok?
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_smoke").count

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_smoke")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 10, @user.reload.bid_credits

    refund_payload = {
      id: "evt_refund_smoke",
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_smoke",
          payment_intent: "pi_smoke",
          amount_refunded: 999,
          refunds: { data: [ { id: "re_smoke" } ] }
        }
      }
    }

    first_refund = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    assert first_refund.ok?

    second_refund = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    assert second_refund.ok?
    assert_equal :duplicate, second_refund.code

    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_smoke").count
    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "purchase_refund_credit_reversal").count
    assert_equal "refunded", purchase.reload.status
    assert_equal 0, @user.reload.bid_credits
  end
end
