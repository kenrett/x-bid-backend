require "test_helper"
require "ostruct"
require "stringio"

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

  test "applies charge.refunded to purchase and reconciles credits" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 500,
      currency: "usd",
      stripe_payment_intent_id: "pi_123",
      status: "completed"
    )

    Credits::Apply.apply!(
      user: @user,
      reason: "bid_pack_purchase",
      amount: @bid_pack.bids,
      idempotency_key: "purchase:#{purchase.id}:grant",
      kind: :grant,
      purchase: purchase,
      stripe_payment_intent_id: "pi_123",
      metadata: { source: "test" }
    )
    assert_equal 500, @user.reload.bid_credits

    refund_payload = {
      id: "evt_refund_1",
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_123",
          payment_intent: "pi_123",
          amount_refunded: 500,
          refunds: {
            data: [
              { id: "re_1" }
            ]
          }
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))

    assert result.ok?
    assert_equal "refunded", purchase.reload.status
    assert_equal 500, purchase.refunded_cents
    assert_equal "re_1", purchase.refund_id
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal(-500, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").sum(:amount_cents))
    assert_equal 0, @user.reload.bid_credits
    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "purchase_refund_credit_reversal").count
  end

  test "duplicate refund webhook deliveries are harmless" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 500,
      currency: "usd",
      stripe_payment_intent_id: "pi_123",
      status: "completed"
    )

    Credits::Apply.apply!(
      user: @user,
      reason: "bid_pack_purchase",
      amount: @bid_pack.bids,
      idempotency_key: "purchase:#{purchase.id}:grant",
      kind: :grant,
      purchase: purchase,
      stripe_payment_intent_id: "pi_123",
      metadata: { source: "test" }
    )

    refund_object = {
      id: "ch_123",
      payment_intent: "pi_123",
      amount_refunded: 500,
      refunds: { data: [ { id: "re_1" } ] }
    }

    first = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(id: "evt_refund_a", type: "charge.refunded", data: { object: refund_object }))
    assert first.ok?

    second = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(id: "evt_refund_b", type: "charge.refunded", data: { object: refund_object }))
    assert second.ok?

    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "purchase_refund_credit_reversal").count
  end

  test "violations are observable in logs when Stripe succeeds without purchase creation" do
    io = StringIO.new
    logger = Logger.new(io)

    Rails.stub(:logger, logger) do
      Payments::ApplyBidPackPurchase.stub(:call!, ServiceResult.ok(data: { purchase: nil })) do
        result = Stripe::WebhookEvents::Process.call(event: @event)
        refute result.ok?
        assert_equal :processing_error, result.code
      end
    end

    output = io.string
    assert_includes output, "\"event\":\"stripe.payment_succeeded.purchase_not_created\""
    assert_includes output, "\"payment_intent_id\":\"pi_123\""
  end

  test "replays are retry-safe when the first attempt fails after persisting the event" do
    calls = 0
    original = Payments::ApplyBidPackPurchase.method(:call!)

    Payments::ApplyBidPackPurchase.stub(:call!, lambda { |**kwargs|
      calls += 1
      raise "boom" if calls == 1
      original.call(**kwargs)
    }) do
      first = Stripe::WebhookEvents::Process.call(event: @event)
      refute first.ok?
      assert_equal :processing_error, first.code

      second = Stripe::WebhookEvents::Process.call(event: @event)
      assert second.ok?
    end

    assert_equal 500, @user.reload.bid_credits
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_123")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_123").count
    assert StripeEvent.find_by!(stripe_event_id: "evt_123").processed_at.present?
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

  test "DB constraints prevent double-credit for the same purchase even with a different idempotency key" do
    Stripe::WebhookEvents::Process.call(event: @event)
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_123")

    assert_raises(ActiveRecord::RecordNotUnique) do
      CreditTransaction.create!(
        user: @user,
        kind: "grant",
        amount: @bid_pack.bids,
        reason: "bid_pack_purchase",
        idempotency_key: "purchase:#{purchase.id}:grant:evil",
        purchase: purchase,
        stripe_payment_intent_id: purchase.stripe_payment_intent_id,
        stripe_checkout_session_id: purchase.stripe_checkout_session_id,
        metadata: {}
      )
    end
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

  test "creates purchase and credits user on checkout.session.completed" do
    payload = {
      id: "evt_cs_123",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_123",
          payment_status: "paid",
          payment_intent: "pi_cs_123",
          metadata: { user_id: @user.id, bid_pack_id: @bid_pack.id },
          amount_total: 600,
          currency: "usd"
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))

    assert result.success?, "Expected processing to succeed"
    purchase = Purchase.find_by(stripe_checkout_session_id: "cs_123")
    assert_not_nil purchase, "Purchase should be created"
    assert_equal "completed", purchase.status
    assert_equal "pi_cs_123", purchase.stripe_payment_intent_id
    assert_equal 600, purchase.amount_cents
    assert_equal @bid_pack.id, purchase.bid_pack_id
    assert_equal @user.id, purchase.user_id
    assert_equal @bid_pack.bids, @user.reload.bid_credits
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_cs_123").count
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  test "checkout.session.completed duplicate deliveries are idempotent" do
    payload = {
      id: "evt_cs_dup",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_dup",
          payment_status: "paid",
          payment_intent: "pi_cs_dup",
          metadata: { user_id: @user.id, bid_pack_id: @bid_pack.id },
          amount_total: 500,
          currency: "usd"
        }
      }
    }

    first = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
    assert first.ok?
    credits_after_first = @user.reload.bid_credits

    second = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
    assert second.ok?
    assert_equal :duplicate, second.code
    assert_equal true, second.data[:idempotent]
    assert_equal credits_after_first, @user.reload.bid_credits
    assert_equal 1, Purchase.where(stripe_checkout_session_id: "cs_dup").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_cs_dup").count
  end

  test "checkout.session.completed with different event IDs but same session/payment is idempotent" do
    base_object = {
      id: "cs_same",
      payment_status: "paid",
      payment_intent: "pi_same",
      metadata: { user_id: @user.id, bid_pack_id: @bid_pack.id },
      amount_total: 500,
      currency: "usd"
    }

    first_payload = { id: "evt_cs_same_a", type: "checkout.session.completed", data: { object: base_object } }
    second_payload = { id: "evt_cs_same_b", type: "checkout.session.completed", data: { object: base_object } }

    first = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(first_payload))
    assert first.ok?
    credits_after_first = @user.reload.bid_credits

    second = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(second_payload))
    assert second.ok?
    assert_equal credits_after_first, @user.reload.bid_credits

    assert_equal 1, Purchase.where(stripe_checkout_session_id: "cs_same").count
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_same").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_same").count
    assert_equal 2, StripeEvent.where(stripe_event_id: [ "evt_cs_same_a", "evt_cs_same_b" ]).count
  end

  test "out-of-order refund before purchase converges correctly on replay" do
    refund_object = {
      id: "ch_oor_1",
      payment_intent: "pi_oor_1",
      amount_refunded: 500,
      refunds: { data: [ { id: "re_oor_1" } ] }
    }

    refund_payload = { id: "evt_refund_oor", type: "charge.refunded", data: { object: refund_object } }
    first_refund = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    refute first_refund.ok?
    assert_equal :not_found, first_refund.code
    assert_equal 0, @user.reload.bid_credits

    purchase_payload = @event_payload.deep_dup
    purchase_payload[:id] = "evt_purchase_oor"
    purchase_payload[:data][:object][:id] = "pi_oor_1"
    purchase = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(purchase_payload))
    assert purchase.ok?
    assert_equal 500, @user.reload.bid_credits

    second_refund = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(refund_payload))
    assert second_refund.ok?
    assert_equal 0, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_oor_1").count
    assert_equal 1, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_oor_1").count
    assert_equal(-500, MoneyEvent.where(event_type: :refund, source_type: "StripePaymentIntent", source_id: "pi_oor_1").sum(:amount_cents))
  end

  test "concurrent webhook processing applies credits exactly once for the same payment intent" do
    base_payload = @event_payload.deep_dup
    base_payload[:data][:object][:id] = "pi_concurrent_1"

    start = Queue.new
    ready = Queue.new
    results = Queue.new
    threads =
      5.times.map do |idx|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            payload = base_payload.deep_dup
            payload[:id] = "evt_concurrent_#{idx}"
            results << Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
          end
        end
      end

    5.times { ready.pop }
    5.times { start << true }
    threads.each(&:join)

    5.times do
      result = results.pop
      assert result.ok?
    end

    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_concurrent_1").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_concurrent_1").count
    assert_equal @bid_pack.bids, @user.reload.bid_credits

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_concurrent_1")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 5, StripeEvent.where(stripe_event_id: (0...5).map { |i| "evt_concurrent_#{i}" }).count
  end

  test "partial failure during credit application converges correctly on replay" do
    payload = @event_payload.deep_dup
    payload[:id] = "evt_partial_failure"
    payload[:data][:object][:id] = "pi_partial_failure"
    event = FakeStripeEvent.new(payload)

    calls = 0
    original_apply = Credits::Apply.method(:apply!)
    Credits::Apply.stub(:apply!, lambda { |**kwargs|
      calls += 1
      raise "boom" if calls == 1
      original_apply.call(**kwargs)
    }) do
      first = Stripe::WebhookEvents::Process.call(event: event)
      refute first.ok?
      assert_equal :processing_error, first.code

      assert_equal 0, Purchase.where(stripe_payment_intent_id: "pi_partial_failure").count
      assert_equal 0, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_partial_failure").count
      assert_equal 0, @user.reload.bid_credits

      second = Stripe::WebhookEvents::Process.call(event: event)
      assert second.ok?
    end

    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_partial_failure").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_partial_failure").count
    assert_equal @bid_pack.bids, @user.reload.bid_credits
  end

  test "checkout.session.completed fails when metadata is missing" do
    payload = {
      id: "evt_cs_missing_meta",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_missing_meta",
          payment_status: "paid",
          payment_intent: "pi_missing_meta",
          metadata: nil,
          amount_total: 500,
          currency: "usd"
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))

    refute result.ok?
    assert_equal :missing_metadata, result.code
    assert_equal 0, Purchase.where(stripe_checkout_session_id: "cs_missing_meta").count
    assert_equal 0, @user.reload.bid_credits
  end

  test "checkout.session.completed fails when user is missing" do
    payload = {
      id: "evt_cs_missing_user",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_missing_user",
          payment_status: "paid",
          payment_intent: "pi_missing_user",
          metadata: { user_id: 999_999, bid_pack_id: @bid_pack.id },
          amount_total: 500,
          currency: "usd"
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))

    refute result.ok?
    assert_equal :user_not_found, result.code
    assert_equal 0, Purchase.where(stripe_checkout_session_id: "cs_missing_user").count
  end

  test "checkout.session.completed fails when bid pack is missing" do
    payload = {
      id: "evt_cs_missing_bid_pack",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_missing_bid_pack",
          payment_status: "paid",
          payment_intent: "pi_missing_bid_pack",
          metadata: { user_id: @user.id, bid_pack_id: 999_999 },
          amount_total: 500,
          currency: "usd"
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))

    refute result.ok?
    assert_equal :bid_pack_not_found, result.code
    assert_equal 0, Purchase.where(stripe_checkout_session_id: "cs_missing_bid_pack").count
  end

  test "checkout.session.completed ignores sessions that are not paid" do
    payload = {
      id: "evt_cs_unpaid",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_unpaid",
          payment_status: "unpaid",
          payment_intent: "pi_unpaid",
          metadata: { user_id: @user.id, bid_pack_id: @bid_pack.id },
          amount_total: 500,
          currency: "usd"
        }
      }
    }

    result = Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))

    assert result.ok?
    assert_equal :ignored, result.code
    assert_equal 0, Purchase.where(stripe_checkout_session_id: "cs_unpaid").count
    assert_equal 0, @user.reload.bid_credits
  end
end
