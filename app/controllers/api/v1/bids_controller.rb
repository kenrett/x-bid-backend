module Api
  module V1
    class BidsController < ApplicationController
      before_action :authenticate_request!

      resource_description do
        short 'Bidding on auctions'
      end

      api :POST, '/auctions/:auction_id/bids', 'Place a bid on an auction'
      description 'Places a bid on behalf of the authenticated user. Requires a valid JWT.'
      param :auction_id, :number, desc: 'ID of the auction to bid on', required: true
      error code: 401, desc: 'Unauthorized'
      error code: 422, desc: 'Unprocessable Entity (e.g., auction not active, insufficient credits)'
      def create
        auction = Auction.find(params[:auction_id])
        result = PlaceBid.new(user: @current_user, auction: auction).call

        if result.success?
          # After a successful bid, include the user's new credit balance in the response
          # so the frontend can update its state immediately.
          # We use a serializer for the bid to ensure consistent formatting.
          render json: {
            success: true, bid: BidSerializer.new(result.bid).as_json, bidCredits: @current_user.bid_credits
          }, status: :ok
        else
          render json: { success: false, error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end