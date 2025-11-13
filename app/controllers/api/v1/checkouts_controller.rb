class Api::V1::CheckoutsController < ApplicationController
  before_action :authenticate_request! # Use the app's custom JWT authentication

  def create
    bid_pack = BidPack.find(params[:bid_pack_id])
    # debugger

    begin
      # Stripe redirects the user here after they complete the payment flow.
      return_url = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/purchase-status?session_id={CHECKOUT_SESSION_ID}"

      @session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [
          {
            # Use price_data for dynamic pricing. 'price' expects a Stripe Price ID.
            price_data: {
              currency: 'usd',
              product_data: {
                name: bid_pack.name,
              },
              unit_amount: (bid_pack.price * 100).to_i, # Price in cents
            },
            quantity: 1,
          },
        ],
        mode: 'payment',
        ui_mode: 'embedded',
        return_url: return_url,
        customer_email: @current_user.email_address, # Pre-fill customer email
        metadata: {
          user_id: @current_user.id,
          bid_pack_id: bid_pack.id
        }
      })
      # For embedded UI mode, you must return the client_secret to the frontend.
      render json: { clientSecret: @session.client_secret }, status: :ok
    rescue Stripe::InvalidRequestError => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Bid pack not found" }, status: :not_found
    end
  end

  def status
    if Purchase.exists?(stripe_checkout_session_id: params[:session_id])
      # The reload ensures we get the most up-to-date credit balance.
      return render json: { status: 'success', message: 'This purchase has already been processed.', updated_bid_credits: @current_user.reload.bid_credits }, status: :already_reported
    end

    session = Stripe::Checkout::Session.retrieve(params[:session_id])
  
    if session.payment_status == 'paid'
      ActiveRecord::Base.transaction do
        bid_pack = BidPack.find(session.metadata.bid_pack_id)
        
        Purchase.create!(
          user: @current_user,
          bid_pack: bid_pack,
          stripe_checkout_session_id: session.id,
          status: 'completed'
        )

        @current_user.increment!(:bid_credits, bid_pack.bids)
      end

      render json: { status: 'success', message: 'Purchase successful!', updated_bid_credits: @current_user.reload.bid_credits }, status: :ok
    else
      render json: { status: 'error', error: 'Payment was not successful.' }, status: :unprocessable_entity
    end
  rescue Stripe::InvalidRequestError => e
    render json: { status: 'error', error: "Invalid session ID: #{e.message}" }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { status: 'error', error: "Failed to record purchase: #{e.message}" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { status: 'success', message: 'This purchase has already been processed.', updated_bid_credits: @current_user.reload.bid_credits }, status: :ok
  end

  def success
    session_id = params[:session_id]
    @session = Stripe::Checkout::Session.retrieve(session_id)

    # TODO: verify the session and fulfill the purchase,
    # e.g., by calling the PurchaseBidPack service.
    # For now, just return the session details.
    render json: { message: "Purchase successful!", session: @session }, status: :ok
  end
end