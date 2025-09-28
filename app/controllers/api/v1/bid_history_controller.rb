module Api
  module V1
    class BidHistoryController < ApplicationController
      before_action :set_auction

      # GET /api/v1/auctions/:auction_id/bid_history
      def index
        bids = @auction.bids.order(created_at: :desc).includes(:user)

        render json: {
          auction: {
            winning_user_id: @auction.winning_user_id,
            winning_user_name: @auction.winning_user&.name
          },
          # Use SerializableResource to correctly apply the serializer to the collection
          bids: ActiveModelSerializers::SerializableResource.new(bids, each_serializer: BidHistorySerializer)
        }
      end

      private

      def set_auction
        @auction = Auction.find(params[:auction_id])
      end
    end
  end
end
