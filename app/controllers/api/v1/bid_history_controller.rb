module Api
  module V1
    class BidHistoryController < ApplicationController
      before_action :set_auction

      resource_description do
        short "Auction Bid History"
      end

      api :GET, "/auctions/:auction_id/bid_history", "List the bid history for an auction"
      param :auction_id, :number, desc: "ID of the auction", required: true
      error code: 404, desc: "Not Found - The auction with the specified ID was not found."

      # GET /api/v1/auctions/:auction_id/bid_history
      def index
        bids = @auction.bids.order(created_at: :desc).includes(:user)

        render json: {
          auction: {
            winning_user_id: @auction.winning_user_id,
            winning_user_name: @auction.winning_user&.name
          },
          bids: bids.map { |bid| BidSerializer.new(bid).as_json }
        }
      end

      private

      def set_auction
        @auction = Auction.find(params[:auction_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Auction not found" }, status: :not_found
      end
    end
  end
end
