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
    @bid_pack = BidPack.create!(name: "Starter Pack", bids: 10, price: 5.00, active: true, status: :active)
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
  end

  test "is idempotent when the same Stripe event is replayed" do
    Stripe::WebhookEvents::Process.call(event: @event)
    credits_after_first = @user.reload.bid_credits

    duplicate_event = FakeStripeEvent.new(@event_payload)
    result = Stripe::WebhookEvents::Process.call(event: duplicate_event)

    assert result.success?, "Duplicate processing should be treated as success"
    assert_equal credits_after_first, @user.reload.bid_credits, "Credits should not change on replay"
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_123").count
  end
end
