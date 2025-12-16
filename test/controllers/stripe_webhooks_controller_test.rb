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

  test "verifies signature and forwards to processor" do
    event = OpenStruct.new(id: "evt_ctrl", type: "payment_intent.succeeded", data: OpenStruct.new(object: {}), to_hash: {})
    payload = { id: "evt_ctrl" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(body, signature, secret) {
      assert_equal payload, body
      assert_equal "sig_header", signature
      assert_equal @secret, secret
      event
    }) do
      Stripe::WebhookEvents::Process.stub(:call, ServiceResult.ok(code: :processed, message: "ok")) do
        post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
        assert_response :success
        body = JSON.parse(response.body)
        assert_equal "processed", body["status"]
      end
    end
  end

  test "returns bad_request on invalid signature" do
    payload = { id: "evt_bad" }.to_json

    Stripe::Webhook.stub(:construct_event, ->(*_) { raise Stripe::SignatureVerificationError.new("bad", "payload") }) do
      post "/api/v1/stripe/webhooks", params: payload, headers: { "Stripe-Signature" => "sig_header" }
      assert_response :bad_request
    end
  end
end
