require "uri"
require Rails.root.join("app/lib/frontend_origins")

class Api::V1::CheckoutsController < ApplicationController
  before_action :authenticate_request!
  before_action :require_verified_email!, only: %i[create success]

  # @summary Start a Stripe Checkout session for a bid pack
  # Initializes a Stripe checkout session for the given bid pack and returns the client secret.
  # @parameter bid_pack_id(query) [Integer] ID of the bid pack to purchase
  # @response Checkout session created (200) [CheckoutSession]
  # @response Unauthorized (401) [Error]
  # @response Not found (404) [Error]
  # @response Validation error (422) [Error]
  def create
    bid_pack = BidPack.active.find(params[:bid_pack_id])
    purchase = nil
    begin
      origin = resolve_frontend_origin
      return_url = "#{origin}/purchase-status?session_id={CHECKOUT_SESSION_ID}"

      purchase = Purchase.create!(
        user: @current_user,
        bid_pack: bid_pack,
        amount_cents: (bid_pack.price.to_d * 100).to_i,
        currency: "usd",
        status: "created",
        storefront_key: Current.storefront_key
      )

      AppLogger.log(
        event: "checkout.create.started",
        bid_pack_id: bid_pack.id,
        frontend_origin: origin,
        return_url: return_url
      )

      @session = Stripe::Checkout::Session.create({
        payment_method_types: [ "card" ],
        line_items: [
            {
              price_data: {
                currency: "usd",
                product_data: {
                name: bid_pack.name
              },
              unit_amount: (bid_pack.price * 100).to_i # Price in cents
            },
            quantity: 1
          }
        ],
        mode: "payment",
        ui_mode: "embedded",
        return_url: return_url,
        customer_email: @current_user.email_address, # Pre-fill customer email
        metadata: {
          user_id: @current_user.id,
          bid_pack_id: bid_pack.id,
          purchase_id: purchase.id
        },
        payment_intent_data: {
          metadata: {
            user_id: @current_user.id,
            bid_pack_id: bid_pack.id,
            purchase_id: purchase.id
          }
        }
      })
      purchase.update!(
        stripe_checkout_session_id: @session.id,
        stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || (@session.payment_intent if @session.respond_to?(:payment_intent))
      )
      AuditLogger.log(
        action: "checkout.created",
        actor: @current_user,
        user: @current_user,
        request: request,
        payload: {
          bid_pack_id: bid_pack.id,
          stripe_checkout_session_id: (@session.id if @session.respond_to?(:id)),
          payment_status: (@session.payment_status if @session.respond_to?(:payment_status))
        }.compact
      )
      AppLogger.log(
        event: "checkout.create.succeeded",
        bid_pack_id: bid_pack.id,
        stripe_checkout_session_id: (@session.id if @session.respond_to?(:id)),
        purchase_id: purchase.id
      )
      AppLogger.log(
        event: "purchase.created",
        purchase_id: purchase.id,
        user_id: @current_user.id,
        bid_pack_id: bid_pack.id,
        stripe_checkout_session_id: purchase.stripe_checkout_session_id,
        stripe_payment_intent_id: purchase.stripe_payment_intent_id,
        status: purchase.status
      )
      render json: { clientSecret: @session.client_secret }, status: :ok
    rescue Stripe::InvalidRequestError => e
      purchase&.update!(status: "failed") if purchase&.persisted? && purchase.status != "failed"
      AppLogger.error(event: "checkout.create.failed", error: e, bid_pack_id: bid_pack&.id)
      render_error(code: :stripe_error, message: e.message, status: :unprocessable_content)
    rescue ActiveRecord::RecordNotFound
      render_error(code: :not_found, message: "Bid pack not found", status: :not_found)
    end
  end

  # @summary Check the Stripe checkout session status
  # Fetches the status of a Stripe checkout session using its ID.
  # @parameter session_id(query) [String] ID of the Stripe checkout session
  # @response Checkout status (200) [CheckoutSession]
  # @response Unauthorized (401) [Error]
  # @response Not found (404) [Error]
  def status
    session = Stripe::Checkout::Session.retrieve(params[:session_id])

    ownership_error = validate_checkout_session_ownership(session)
    if ownership_error
      return render_error(code: :forbidden, message: ownership_error, status: :forbidden)
    end

    AppLogger.log(
      event: "checkout.status.read",
      stripe_checkout_session_id: session.id,
      payment_status: session.payment_status,
      session_status: session.status
    )
    render json: { payment_status: session.payment_status, status: session.status }, status: :ok
  rescue Stripe::InvalidRequestError => e
    render_error(code: :not_found, message: "Invalid session ID: #{e.message}", status: :not_found)
  end

  # @summary Handle successful checkout callbacks and credit the user
  # Returns the current status of the checkout session without mutating state.
  # @parameter session_id(query) [String] ID of the Stripe checkout session
  # @response Checkout status (200) [CheckoutStatus]
  # @response Unauthorized (401) [Error]
  # @response Not found (404) [Error]
  def success
    session_id = params[:session_id].to_s
    purchase = Purchase.find_by(stripe_checkout_session_id: session_id)
    if purchase.blank? || purchase.user_id != @current_user.id
      return render_error(code: :not_found, message: "Purchase not found", status: :not_found)
    end

    status = case purchase.status.to_s
    when "applied", "refunded", "partially_refunded" then "applied"
    when "failed", "voided" then "failed"
    else "pending"
    end

    AppLogger.log(
      event: "checkout.success.status",
      purchase_id: purchase.id,
      user_id: @current_user.id,
      stripe_checkout_session_id: purchase.stripe_checkout_session_id,
      stripe_payment_intent_id: purchase.stripe_payment_intent_id,
      status: status
    )

    render json: {
      status: status,
      purchase_id: purchase.id,
      message: (status == "pending" ? "Payment is still processing." : nil)
    }.compact, status: :ok
  end

  def validate_checkout_session_ownership(session)
    metadata = session.respond_to?(:metadata) ? session.metadata : nil
    metadata_user_id = metadata&.respond_to?(:user_id) ? metadata.user_id : nil
    metadata_user_id = metadata_user_id.to_s.presence

    if metadata_user_id.blank?
      return "Forbidden: checkout session is missing ownership metadata."
    end

    if metadata_user_id != @current_user.id.to_s
      return "Forbidden: checkout session does not belong to the current user."
    end

    customer_email = session.respond_to?(:customer_email) ? session.customer_email.to_s.presence : nil
    if customer_email.present? && customer_email.downcase != @current_user.email_address.to_s.downcase
      return "Forbidden: checkout session email does not match the current user."
    end

    nil
  end

  def resolve_frontend_origin
    allowed = FrontendOrigins.for_env!

    origin = normalize_origin(request.headers["Origin"])
    return origin if origin.present? && allowed.include?(origin)

    referer_origin = normalize_origin(referer_origin_from(request.referer))
    return referer_origin if referer_origin.present? && allowed.include?(referer_origin)

    allowed.first
  end

  def referer_origin_from(referer)
    return if referer.blank?

    uri = URI.parse(referer.to_s)
    return if uri.scheme.blank? || uri.host.blank?

    default_port = uri.scheme == "https" ? 443 : 80
    port_part = uri.port.present? && uri.port != default_port ? ":#{uri.port}" : ""
    "#{uri.scheme}://#{uri.host}#{port_part}"
  rescue URI::InvalidURIError
    nil
  end

  def normalize_origin(origin)
    origin.to_s.strip.delete_suffix("/").presence
  end
end
