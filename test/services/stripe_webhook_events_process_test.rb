require "test_helper"
require "ostruct"

class StripeWebhookEventsProcessTest < ActiveSupport::TestCase
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

  def setup
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", bid_credits: 0, role: :user)
    @bid_pack = BidPack.create!(name: "Starter Pack", bids: 500, price: 5.00, active: true, status: :active)
    @event_payload = {
      id: "evt_123",
      type: "payment_intent.succeeded",
      data: {
        object: {
          id: "pi_123",
          metadata: {
            user_id: @user.id,
            bid_pack_id: @bid_pack.id
          },
          amount_received: 500,
          currency: "usd"
        }
      }
    }
    @event = FakeStripeEvent.new(@event_payload)
  end

  test "creates purchase and credits user on payment_intent.succeeded" do
    result = Stripe::WebhookEvents::Process.call(event: @event)

    assert result.success?, "Expected processing to succeed"
    purchase = Purchase.find_by(stripe_payment_intent_id: "pi_123")
    assert_not_nil purchase, "Purchase should be created"
    assert_equal "completed", purchase.status
    assert_equal @bid_pack.id, purchase.bid_pack_id
    assert_equal @user.id, purchase.user_id
    assert_equal @bid_pack.bids, @user.reload.bid_credits
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_123").count
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal "pending", purchase.receipt_status
  end

  test "is idempotent when the same Stripe event is replayed" do
    Stripe::WebhookEvents::Process.call(event: @event)
    credits_after_first = @user.reload.bid_credits
    money_events_after_first = MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count

    duplicate_event = FakeStripeEvent.new(@event_payload)
    result = Stripe::WebhookEvents::Process.call(event: duplicate_event)

    assert result.success?, "Duplicate processing should be treated as success"
    assert_equal :duplicate, result.code
    assert_equal true, result.data[:idempotent]
    assert_equal credits_after_first, @user.reload.bid_credits, "Credits should not change on replay"
    assert_equal money_events_after_first, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_123").count
  end

  test "does not double-credit when different Stripe events reference the same payment intent" do
    Stripe::WebhookEvents::Process.call(event: @event)
    credits_after_first = @user.reload.bid_credits
    money_events_after_first = MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count

    second_payload = @event_payload.deep_dup
    second_payload[:id] = "evt_124"
    second_event = FakeStripeEvent.new(second_payload)
    result = Stripe::WebhookEvents::Process.call(event: second_event)

    assert result.success?
    assert_equal credits_after_first, @user.reload.bid_credits
    assert_equal money_events_after_first, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    assert_equal 2, StripeEvent.where(stripe_event_id: [ "evt_123", "evt_124" ]).count
  end

  test "webhook and checkout success are idempotent regardless of order" do
    checkout_result = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_123",
      stripe_payment_intent_id: "pi_123",
      stripe_event_id: nil,
      amount_cents: 500,
      currency: "usd",
      source: "checkout_success"
    )
    assert checkout_result.ok?
    assert_equal 500, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count

    webhook_payload = @event_payload.deep_dup
    webhook_payload[:id] = "evt_125"
    webhook_event = FakeStripeEvent.new(webhook_payload)
    webhook_result = Stripe::WebhookEvents::Process.call(event: webhook_event)
    assert webhook_result.ok?
    assert_equal 500, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count

    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_123")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  test "webhook then checkout success does not double-credit" do
    user = User.create!(name: "Buyer 2", email_address: "buyer2@example.com", password: "password", bid_credits: 0, role: :user)
    bid_pack = BidPack.create!(name: "Starter Pack 2", bids: 500, price: 5.00, active: true, status: :active)

    payload = @event_payload.deep_dup
    payload[:id] = "evt_126"
    payload[:data][:object][:metadata] = { user_id: user.id, bid_pack_id: bid_pack.id }
    event = FakeStripeEvent.new(payload)

    webhook_result = Stripe::WebhookEvents::Process.call(event: event)
    assert webhook_result.ok?
    assert_equal 500, user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count

    checkout_result = Payments::ApplyBidPackPurchase.call!(
      user: user,
      bid_pack: bid_pack,
      stripe_checkout_session_id: "cs_456",
      stripe_payment_intent_id: "pi_123",
      stripe_event_id: "evt_126",
      amount_cents: 500,
      currency: "usd",
      source: "checkout_success"
    )

    assert checkout_result.ok?
    assert_equal 500, user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
  end
end
