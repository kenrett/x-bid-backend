require "test_helper"
require "ostruct"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "whsec_test"
    ENV["STRIPE_WEBHOOK_SECRET"] = @secret
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "returns 500 when STRIPE_WEBHOOK_SECRET is missing" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")

    post "/api/v1/stripe/webhooks", params: { id: "evt_missing_secret" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
    assert_response :internal_server_error
    body = JSON.parse(response.body)
    assert_equal "stripe_webhook_missing_secret", body.dig("error", "code").to_s
    assert_equal "Webhook secret not configured", body.dig("error", "message")
  end

  test "verifies signature, forwards to processor, and returns 200 with status/message" do
    constructed_event = OpenStruct.new(id: "evt_ctrl", type: "payment_intent.succeeded", data: OpenStruct.new(object: {}), to_hash: {})
    payload = { id: "evt_ctrl" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(body, signature, secret) {
      assert_equal payload, body
      assert_equal "sig_header", signature
      assert_equal @secret, secret
      constructed_event
    }) do
      Stripe::WebhookEvents::Process.stub(:call, ->(event:) {
        assert_equal constructed_event, event
        ServiceResult.ok(code: :processed, message: "ok")
      }) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal "processed", body["status"]
        assert_equal "ok", body["message"]
      end
    end
  end

  test "returns 400 on invalid signature and logs stripe.webhook.invalid_signature" do
    payload = { id: "evt_bad" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(*_) { raise Stripe::SignatureVerificationError.new("bad", "payload") }) do
      AppLogger.stub(:log, lambda { |event:, **context|
        assert_equal "stripe.webhook.invalid_signature", event
        assert_includes context[:error_message].to_s, "bad"
      }) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :bad_request
        body = JSON.parse(response.body)
        assert_equal "stripe_webhook_invalid_signature", body.dig("error", "code").to_s
        assert_equal "Invalid webhook signature", body.dig("error", "message")
      end
    end
  end

  test "returns 422 when processor returns failure" do
    event = OpenStruct.new(id: "evt_fail", type: "payment_intent.succeeded", data: OpenStruct.new(object: {}), to_hash: {})
    payload = { id: "evt_fail" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
      Stripe::WebhookEvents::Process.stub(:call, ServiceResult.fail("nope", code: :invalid_amount)) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :unprocessable_content
        body = JSON.parse(response.body)
        assert_equal "invalid_amount", body.dig("error", "code").to_s
        assert_equal "nope", body.dig("error", "message")
      end
    end
  end

  test "replayed Stripe webhook event does not double-credit" do
    user = User.create!(name: "Buyer", email_address: "buyer_webhook@example.com", password: "password", role: :user, bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)

    object = {
      id: "pi_replay",
      amount_received: 100,
      currency: "usd",
      metadata: { user_id: user.id, bid_pack_id: bid_pack.id }
    }
    event = OpenStruct.new(
      id: "evt_replay",
      type: "payment_intent.succeeded",
      data: OpenStruct.new(object: object),
      livemode: false,
      to_hash: { id: "evt_replay", type: "payment_intent.succeeded", data: { object: object } }
    )

    payload = { id: "evt_replay" }.to_json

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits

        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits
      end
    end

    assert_equal 1, Purchase.where(user_id: user.id, stripe_payment_intent_id: "pi_replay").count
    purchase = Purchase.find_by!(user_id: user.id, stripe_payment_intent_id: "pi_replay")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_replay").count
  end

  test "different Stripe event IDs for the same payment intent do not double-credit" do
    user = User.create!(name: "Buyer", email_address: "buyer_webhook_dupe_pi@example.com", password: "password", role: :user, bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)

    object = {
      id: "pi_dupe_pi",
      amount_received: 100,
      currency: "usd",
      metadata: { user_id: user.id, bid_pack_id: bid_pack.id }
    }

    events = [
      OpenStruct.new(
        id: "evt_dupe_a",
        type: "payment_intent.succeeded",
        data: OpenStruct.new(object: object),
        livemode: false,
        to_hash: { id: "evt_dupe_a", type: "payment_intent.succeeded", data: { object: object } }
      ),
      OpenStruct.new(
        id: "evt_dupe_b",
        type: "payment_intent.succeeded",
        data: OpenStruct.new(object: object),
        livemode: false,
        to_hash: { id: "evt_dupe_b", type: "payment_intent.succeeded", data: { object: object } }
      )
    ]

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { events.shift }) do
        post "/api/v1/stripe/webhooks", params: { id: "evt_dupe_a" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits

        post "/api/v1/stripe/webhooks", params: { id: "evt_dupe_b" }.to_json, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits
      end
    end

    assert_equal 1, Purchase.where(user_id: user.id, stripe_payment_intent_id: "pi_dupe_pi").count
    assert_equal 2, StripeEvent.where(stripe_event_id: [ "evt_dupe_a", "evt_dupe_b" ]).count
  end

  test "replayed checkout.session.completed event does not double-credit" do
    user = User.create!(name: "Buyer", email_address: "buyer_cs_webhook@example.com", password: "password", role: :user, bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)

    object = {
      id: "cs_replay",
      payment_status: "paid",
      payment_intent: "pi_replay_cs",
      amount_total: 100,
      currency: "usd",
      metadata: { user_id: user.id, bid_pack_id: bid_pack.id }
    }
    event = OpenStruct.new(
      id: "evt_cs_replay",
      type: "checkout.session.completed",
      data: OpenStruct.new(object: object),
      livemode: false,
      to_hash: { id: "evt_cs_replay", type: "checkout.session.completed", data: { object: object } }
    )

    payload = { id: "evt_cs_replay" }.to_json

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits

        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        assert_equal 10, user.reload.bid_credits
      end
    end

    assert_equal 1, Purchase.where(user_id: user.id, stripe_payment_intent_id: "pi_replay_cs").count
    purchase = Purchase.find_by!(user_id: user.id, stripe_payment_intent_id: "pi_replay_cs")
    assert_equal "cs_replay", purchase.stripe_checkout_session_id
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_cs_replay").count
  end

  test "checkout.session.completed missing metadata returns 422 and does not mutate credits" do
    user = User.create!(name: "Buyer", email_address: "buyer_cs_missing_meta@example.com", password: "password", role: :user, bid_credits: 0)

    object = {
      id: "cs_missing_meta",
      payment_status: "paid",
      payment_intent: "pi_missing_meta",
      amount_total: 100,
      currency: "usd",
      metadata: { user_id: user.id }
    }
    event = OpenStruct.new(
      id: "evt_cs_missing_meta",
      type: "checkout.session.completed",
      data: OpenStruct.new(object: object),
      livemode: false,
      to_hash: { id: "evt_cs_missing_meta", type: "checkout.session.completed", data: { object: object } }
    )

    payload = { id: "evt_cs_missing_meta" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
      post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
      assert_response :unprocessable_content
      body = JSON.parse(response.body)
      assert_equal "missing_metadata", body.dig("error", "code").to_s
    end

    assert_equal 0, user.reload.bid_credits
    assert_equal 0, Purchase.where(user_id: user.id, stripe_payment_intent_id: "pi_missing_meta").count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_cs_missing_meta").count
  end

  test "missing bid_pack_id metadata returns 422 and does not mutate credits" do
    user = User.create!(name: "Buyer", email_address: "buyer_missing_meta@example.com", password: "password", role: :user, bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)

    object = {
      id: "pi_missing_bid_pack_id",
      amount_received: 100,
      currency: "usd",
      metadata: { user_id: user.id }
    }
    event = OpenStruct.new(
      id: "evt_missing_bid_pack_id",
      type: "payment_intent.succeeded",
      data: OpenStruct.new(object: object),
      to_hash: { id: "evt_missing_bid_pack_id", type: "payment_intent.succeeded", data: { object: object } }
    )

    payload = { id: "evt_missing_bid_pack_id" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
      post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
      assert_response :unprocessable_content
      body = JSON.parse(response.body)
      assert_equal "bid_pack_not_found", body.dig("error", "code").to_s
    end

    assert_equal 0, user.reload.bid_credits
    assert_equal 0, Purchase.where(user_id: user.id, stripe_payment_intent_id: "pi_missing_bid_pack_id").count
  end

  test "logs payments.apply_purchase with user/bid_pack/stripe identifiers on success" do
    user = User.create!(name: "Buyer", email_address: "buyer_log@example.com", password: "password", role: :user, bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)

    object = {
      id: "pi_log_webhook",
      amount_received: 100,
      currency: "usd",
      metadata: { user_id: user.id, bid_pack_id: bid_pack.id }
    }
    event = OpenStruct.new(
      id: "evt_log_webhook",
      type: "payment_intent.succeeded",
      data: OpenStruct.new(object: object),
      livemode: false,
      to_hash: { id: "evt_log_webhook", type: "payment_intent.succeeded", data: { object: object } }
    )

    payload = { id: "evt_log_webhook" }.to_json

    logs = []
    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::Webhook.stub(:construct_event, ->(*_) { event }) do
        AppLogger.stub(:log, lambda { |event:, **context|
          logs << { event: event, **context }
        }) do
          post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        end
      end
    end

    assert_response :success
    apply_log = logs.find { |l| l[:event] == "payments.apply_purchase" }
    assert apply_log, "Expected payments.apply_purchase log"
    assert_equal user.id, apply_log[:user_id]
    assert_equal bid_pack.id, apply_log[:bid_pack_id]
    assert_equal "pi_log_webhook", apply_log[:stripe_payment_intent_id]
    assert_equal "evt_log_webhook", apply_log[:stripe_event_id]
  end
end
