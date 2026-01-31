require "test_helper"
require "ostruct"

class EvilPaymentIdempotencyTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "whsec_test"
    ENV["STRIPE_WEBHOOK_SECRET"] = @secret
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "concurrent webhook and redirect apply credits exactly once" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Evil Pack", bids: 25, price: BigDecimal("4.99"), highlight: false, description: "evil", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 499,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_concurrent",
      status: "created"
    )

    event = build_event(
      id: "evt_evil_concurrent",
      type: "checkout.session.completed",
      object: {
        id: "cs_evil_concurrent",
        payment_status: "paid",
        payment_intent: "pi_evil_concurrent",
        metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
        amount_total: 499,
        currency: "usd"
      }
    )

    start = Queue.new
    ready = Queue.new
    results = Queue.new
    webhook_session = open_session
    redirect_session = open_session

    before_credit_tx = CreditTransaction.count
    before_money_events = MoneyEvent.count

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        threads = [
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              webhook_session.post "/api/v1/stripe/webhooks", params: { id: "evt_evil_concurrent" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
              results << webhook_session.response.status
            end
          end,
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              redirect_session.get "/api/v1/checkout/success", params: { session_id: "cs_evil_concurrent" }, headers: auth_headers_for(user)
              results << redirect_session.response.status
            end
          end
        ]

        2.times { ready.pop }
        2.times { start << true }
        threads.each(&:join)
      end
    end

    2.times { results.pop }

    assert_equal before_credit_tx + 1, CreditTransaction.count
    assert_equal before_money_events + 1, MoneyEvent.count
    assert_equal bid_pack.bids, user.reload.bid_credits
    assert_equal "applied", purchase.reload.status
  end

  test "concurrent webhook and status poll apply credits exactly once" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Status Pack", bids: 12, price: BigDecimal("2.00"), highlight: false, description: "status", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 200,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_status",
      status: "created"
    )

    event = build_event(
      id: "evt_evil_status",
      type: "checkout.session.completed",
      object: {
        id: "cs_evil_status",
        payment_status: "paid",
        payment_intent: "pi_evil_status",
        metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
        amount_total: 200,
        currency: "usd"
      }
    )

    status_session = OpenStruct.new(
      id: "cs_evil_status",
      payment_status: "paid",
      status: "complete",
      metadata: OpenStruct.new(user_id: user.id),
      customer_email: user.email_address
    )

    start = Queue.new
    ready = Queue.new
    results = Queue.new
    webhook_session = open_session
    status_session_client = open_session

    before_credit_tx = CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        Stripe::Checkout::Session.stub(:retrieve, ->(_id) { status_session }) do
          threads = [
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                ready << true
                start.pop
                webhook_session.post "/api/v1/stripe/webhooks", params: { id: "evt_evil_status" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
                results << webhook_session.response.status
              end
            end,
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                ready << true
                start.pop
                status_session_client.get "/api/v1/checkout/status", params: { session_id: "cs_evil_status" }, headers: auth_headers_for(user)
                results << status_session_client.response.status
              end
            end
          ]

          2.times { ready.pop }
          2.times { start << true }
          threads.each(&:join)
        end
      end
    end

    2.times { results.pop }

    assert_equal before_credit_tx + 1, CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count
    assert_equal bid_pack.bids, user.reload.bid_credits
    assert_equal "applied", purchase.reload.status
    assert purchase.reload.ledger_grant_credit_transaction_id.present?
  end

  test "different webhook event IDs for the same intent apply exactly once" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Replay Pack", bids: 10, price: BigDecimal("1.00"), highlight: false, description: "replay", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_replay",
      status: "created"
    )

    base_object = {
      id: "cs_evil_replay",
      payment_status: "paid",
      payment_intent: "pi_evil_replay",
      metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
      amount_total: 100,
      currency: "usd"
    }

    events = [
      build_event(id: "evt_evil_replay_a", type: "checkout.session.completed", object: base_object),
      build_event(id: "evt_evil_replay_b", type: "checkout.session.completed", object: base_object)
    ]

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { events.shift }) do
        post "/api/v1/stripe/webhooks", params: { id: "evt_evil_replay_a" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        post "/api/v1/stripe/webhooks", params: { id: "evt_evil_replay_b" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
      end
    end

    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_evil_replay").count
    assert_equal "applied", purchase.reload.status
    assert_equal bid_pack.bids, user.reload.bid_credits
  end

  test "replayed webhook event ID is idempotent" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Replay Single", bids: 7, price: BigDecimal("1.25"), highlight: false, description: "replay", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 125,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_replay_single",
      status: "created"
    )

    event = build_event(
      id: "evt_evil_replay_single",
      type: "checkout.session.completed",
      object: {
        id: "cs_evil_replay_single",
        payment_status: "paid",
        payment_intent: "pi_evil_replay_single",
        metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
        amount_total: 125,
        currency: "usd"
      }
    )

    payload = { id: "evt_evil_replay_single" }.to_json

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        2.times do
          post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
          assert_response :success
        end
      end
    end

    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_evil_replay_single").count
    assert_equal "applied", purchase.reload.status
    assert_equal bid_pack.bids, user.reload.bid_credits
  end

  test "partial failure during credit apply converges on retry" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Retry Pack", bids: 15, price: BigDecimal("2.50"), highlight: false, description: "retry", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 250,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_retry",
      status: "created"
    )

    event = build_event(
      id: "evt_evil_retry",
      type: "checkout.session.completed",
      object: {
        id: "cs_evil_retry",
        payment_status: "paid",
        payment_intent: "pi_evil_retry",
        metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
        amount_total: 250,
        currency: "usd"
      }
    )

    calls = 0
    original = Credits::Apply.method(:apply!)

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        Credits::Apply.stub(:apply!, lambda { |**kwargs|
          calls += 1
          raise "boom" if calls == 1
          original.call(**kwargs)
        }) do
          post "/api/v1/stripe/webhooks", params: { id: "evt_evil_retry" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
          assert_response :unprocessable_content
          assert_equal 0, user.reload.bid_credits

          post "/api/v1/stripe/webhooks", params: { id: "evt_evil_retry" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
          assert_response :success
        end
      end
    end

    assert_equal 1, CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_evil_retry").count
    assert_equal "applied", purchase.reload.status
    assert_equal bid_pack.bids, user.reload.bid_credits
  end

  test "status applied without ledger converges on webhook replay" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Repair Pack", bids: 18, price: BigDecimal("3.00"), highlight: false, description: "repair", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 300,
      currency: "usd",
      stripe_checkout_session_id: "cs_evil_repair",
      stripe_payment_intent_id: "pi_evil_repair",
      status: "applied",
      applied_at: Time.current
    )

    event = build_event(
      id: "evt_evil_repair",
      type: "checkout.session.completed",
      object: {
        id: "cs_evil_repair",
        payment_status: "paid",
        payment_intent: "pi_evil_repair",
        metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
        amount_total: 300,
        currency: "usd"
      }
    )

    before_credit_tx = CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        2.times do
          post "/api/v1/stripe/webhooks", params: { id: "evt_evil_repair" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
          assert_response :success
        end
      end
    end

    assert_equal before_credit_tx + 1, CreditTransaction.where(purchase_id: purchase.id, reason: "bid_pack_purchase").count
    assert_equal "applied", purchase.reload.status
    assert_equal bid_pack.bids, user.reload.bid_credits
    assert purchase.reload.ledger_grant_credit_transaction_id.present?
  end

  private

  def build_event(id:, type:, object:)
    OpenStruct.new(
      id: id,
      type: type,
      data: OpenStruct.new(object: object),
      livemode: false,
      to_hash: { id: id, type: type, data: { object: object } }
    )
  end
end
