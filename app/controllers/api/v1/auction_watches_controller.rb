module Api
  module V1
    class AuctionWatchesController < ApplicationController
      before_action :authenticate_request!

      # POST /api/v1/auctions/:id/watch
      def create
        auction = Auction.find(params[:id])
        AuctionWatch.create!(user: @current_user, auction: auction)
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        head :no_content
      end

      # DELETE /api/v1/auctions/:id/watch
      def destroy
        watch = AuctionWatch.find_by(user_id: @current_user.id, auction_id: params[:id])
        watch&.destroy!
        head :no_content
      end
    end
  end
end
