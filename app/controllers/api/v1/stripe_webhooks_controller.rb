class Api::V1::StripeWebhooksController < ApplicationController
  skip_before_action :authenticate_request!, raise: false
  skip_before_action :enforce_maintenance_mode

  def create
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"]
    if endpoint_secret.blank?
      AppLogger.log(event: "stripe.webhook.missing_secret", level: :error)
      return render_error(code: :stripe_webhook_missing_secret, message: "Webhook secret not configured", status: :internal_server_error)
    end

    event = verify_signature(endpoint_secret)
    return if performed?

    AppLogger.log(
      event: "stripe.webhook.verified",
      stripe_event_id: event.id,
      stripe_event_type: event.type,
      livemode: event.respond_to?(:livemode) ? event.livemode : nil
    )

    result = ::Stripe::WebhookEvents::Process.call(event: event)

    if result.success?
      AppLogger.log(
        event: "stripe.webhook.processed",
        stripe_event_id: event.id,
        stripe_event_type: event.type,
        result_code: result.code
      )
      render json: { status: result.code, message: result.message }, status: :ok
    else
      AppLogger.log(
        event: "stripe.webhook.process_failed",
        level: :error,
        stripe_event_id: event.id,
        stripe_event_type: event.type,
        result_code: result.code,
        result_message: result.error
      )
      render_error(code: result.code || :stripe_webhook_error, message: result.error || "Unable to process Stripe event", status: :unprocessable_content)
    end
  end

  private

  def verify_signature(endpoint_secret)
    payload = request.raw_post
    signature = request.headers["Stripe-Signature"]
    ::Stripe::Webhook.construct_event(payload, signature, endpoint_secret)
  rescue JSON::ParserError, ::Stripe::SignatureVerificationError => e
    AppLogger.log(event: "stripe.webhook.invalid_signature", level: :warn, error_message: e.message)
    render_error(code: :stripe_webhook_invalid_signature, message: "Invalid webhook signature", status: :bad_request)
  end
end
