class Api::V1::CheckoutsController < ApplicationController
  before_action :authenticate_request!

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
      render json: { clientSecret: @session.client_secret }, status: :ok
    rescue Stripe::InvalidRequestError => e
      render json: { error: e.message }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Bid pack not found" }, status: :not_found
    end
  end

  def status
    session = Stripe::Checkout::Session.retrieve(params[:session_id])
  
    render json: { payment_status: session.payment_status, status: session.status }, status: :ok
  rescue Stripe::InvalidRequestError => e
    render json: { status: 'error', error: "Invalid session ID: #{e.message}" }, status: :not_found
  end

  def success
    # If this purchase has already been processed, do nothing more.
    if Purchase.exists?(stripe_checkout_session_id: params[:session_id])
      return render json: { status: 'success', message: 'This purchase has already been processed.', updated_bid_credits: @current_user.reload.bid_credits }, status: :already_reported
    end

    session = Stripe::Checkout::Session.retrieve(params[:session_id])

    # Only fulfill the order if the payment was successful.
    if session.payment_status == 'paid'
      ActiveRecord::Base.transaction do
        bid_pack = BidPack.find(session.metadata.bid_pack_id)
        
        # Create a purchase record to prevent duplicate processing.
        Purchase.create!(
          user: @current_user,
          bid_pack: bid_pack,
          stripe_checkout_session_id: session.id,
          status: 'completed'
        )

        # Atomically increment the user's bid credits.
        @current_user.increment!(:bid_credits, bid_pack.bids)
      end

      render json: { status: 'success', message: 'Purchase successful!', updated_bid_credits: @current_user.reload.bid_credits }, status: :ok
    else
      render json: { status: 'error', error: 'Payment was not successful.' }, status: :unprocessable_entity
    end
  rescue Stripe::InvalidRequestError => e
    render json: { status: 'error', error: "Invalid session ID: #{e.message}" }, status: :not_found
  rescue ActiveRecord::RecordNotUnique
    # This handles a race condition where two requests try to process the same session simultaneously.
    render json: { status: 'success', message: 'This purchase has already been processed.', updated_bid_credits: @current_user.reload.bid_credits }, status: :ok
  end
end
