module Api
  module V1
    class BidHistoryController < ApplicationController
      before_action :set_auction

      # GET /api/v1/auctions/:auction_id/bid_history
      # @summary List bids for a given auction (newest first)
      # Returns the current bid list for an auction along with the winning user, if present.
      # @parameter auction_id(path) [Integer] ID of the auction
      # @response Bid history (200) [BidHistoryResponse]
      # @response Not found (404) [Error]
      # @no_auth
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
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end
    end
  end
end
