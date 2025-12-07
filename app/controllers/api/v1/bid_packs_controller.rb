module Api
  module V1
    class BidPacksController < ApplicationController
      before_action :authenticate_request!, only: [ :purchase ]

      # @summary List available bid packs
      # @no_auth
      def index
        bid_packs = BidPack.active
        render json: bid_packs
      end

      # @summary Purchase a bid pack for the current user
      def purchase
        bid_pack = BidPack.active.find(params[:id])
        result = Billing::PurchaseBidPack.new(user: @current_user, bid_pack: bid_pack).call

        if result.success?
          render json: { message: result.message }, status: :ok
        else
          render_error(code: :bid_pack_purchase_failed, message: result.error, status: :unprocessable_entity)
        end
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Bid pack not found", status: :not_found)
      end
    end
  end
end
