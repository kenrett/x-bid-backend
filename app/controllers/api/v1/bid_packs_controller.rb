module Api
  module V1
    class BidPacksController < ApplicationController
      resource_description do
        short 'Bid Pack management and purchasing'
      end

      before_action :authenticate_request!, only: [:purchase]

      api :GET, '/bid_packs', 'List all available bid packs'
      description 'Returns a list of available bid packs.'
      error code: 200, desc: 'Success'
      def index
        bid_packs = BidPack.active
        render json: bid_packs
      end

      api :POST, '/bid_packs/:id/purchase', 'Purchase a bid pack'
      description 'Purchases a bid pack and credits the user with the bids.'
      param :id, :number, desc: 'ID of the bid pack to purchase', required: true
      error code: 401, desc: 'Unauthorized'
      error code: 404, desc: 'Bid pack not found'
      error code: 422, desc: 'Unprocessable content - purchase failed'
      def purchase
        bid_pack = BidPack.active.find(params[:id])
        result = PurchaseBidPack.new(user: @current_user, bid_pack: bid_pack).call

        if result.success?
          render json: { message: result.message }, status: :ok
        else
          render json: { error: result.error }, status: :unprocessable_content
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Bid pack not found' }, status: :not_found
      end
    end
  end
end
