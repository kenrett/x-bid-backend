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
    assert_equal "stripe_webhook_missing_secret", body["error_code"].to_s
    assert_equal "Webhook secret not configured", body["message"]
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
        assert_equal "stripe_webhook_invalid_signature", body["error_code"].to_s
        assert_equal "Invalid webhook signature", body["message"]
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
        assert_equal "invalid_amount", body["error_code"].to_s
        assert_equal "nope", body["message"]
      end
    end
  end
end
