require "uri"
require Rails.root.join("app/lib/frontend_origins")

class Api::V1::CheckoutsController < ApplicationController
  before_action :authenticate_request!

  # @summary Start a Stripe Checkout session for a bid pack
  # Initializes a Stripe checkout session for the given bid pack and returns the client secret.
  # @parameter bid_pack_id(query) [Integer] ID of the bid pack to purchase
  # @response Checkout session created (200) [CheckoutSession]
  # @response Unauthorized (401) [Error]
  # @response Not found (404) [Error]
  # @response Validation error (422) [Error]
  def create
    bid_pack = BidPack.active.find(params[:bid_pack_id])
    # debugger

    begin
      origin = resolve_frontend_origin
      return_url = "#{origin}/purchase-status?session_id={CHECKOUT_SESSION_ID}"

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
          bid_pack_id: bid_pack.id
        }
      })
      render json: { clientSecret: @session.client_secret }, status: :ok
    rescue Stripe::InvalidRequestError => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Bid pack not found" }, status: :not_found
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

    render json: { payment_status: session.payment_status, status: session.status }, status: :ok
  rescue Stripe::InvalidRequestError => e
    render json: { status: "error", error: "Invalid session ID: #{e.message}" }, status: :not_found
  end

  # @summary Handle successful checkout callbacks and credit the user
  # Idempotently processes a paid checkout session and credits the user with purchased bids.
  # @parameter session_id(query) [String] ID of the Stripe checkout session
  # @response Purchase applied (200) [CheckoutSession]
  # @response Already processed (208) [CheckoutSession]
  # @response Unauthorized (401) [Error]
  # @response Not found (404) [Error]
  # @response Validation error (422) [Error]
  def success
    session = Stripe::Checkout::Session.retrieve(params[:session_id])
    unless session.payment_status == "paid"
      return render json: { status: "error", error: "Payment not completed." }, status: :unprocessable_content
    end

    ownership_error = validate_checkout_session_ownership(session)
    if ownership_error
      return render json: { status: "error", error: ownership_error }, status: :forbidden
    end

    payment_intent_id = session.payment_intent
    bid_pack = BidPack.active.find(session.metadata.bid_pack_id)

    begin
      result = Payments::ApplyBidPackPurchase.call!(
        user: @current_user,
        bid_pack: bid_pack,
        stripe_checkout_session_id: session.id,
        stripe_payment_intent_id: payment_intent_id,
        stripe_event_id: nil,
        amount_cents: (bid_pack.price * 100).to_i,
        currency: "usd",
        source: "checkout_success"
      )
    rescue ActiveRecord::RecordNotUnique
      result = Payments::ApplyBidPackPurchase.call!(
        user: @current_user,
        bid_pack: bid_pack,
        stripe_checkout_session_id: session.id,
        stripe_payment_intent_id: payment_intent_id,
        stripe_event_id: nil,
        amount_cents: (bid_pack.price * 100).to_i,
        currency: "usd",
        source: "checkout_success"
      )
    end

    if result.ok?
      render json: {
        status: "success",
        idempotent: !!result.idempotent,
        purchaseId: result.purchase.id,
        updated_bid_credits: @current_user.reload.bid_credits
      }, status: :ok
    else
      render json: { status: "error", error: result.error }, status: result.http_status
    end
  rescue Stripe::InvalidRequestError => e
    render json: { status: "error", error: "Invalid session ID: #{e.message}" }, status: :not_found
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", error: "Bid pack not found or inactive." }, status: :not_found
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
