module Api
  module V1
    module Me
      class WinsController < ApplicationController
        before_action :authenticate_request!

        # GET /api/v1/me/wins
        # @summary List current user's auction wins (newest first)
        # @response Wins (200) [Array<WonAuction>]
        # @response Unauthorized (401) [Error]
        def index
          result = Auctions::Queries::WonByUser.call(user: @current_user)
          render json: result.records, each_serializer: Api::V1::WonAuctionSerializer, adapter: :attributes
        end

        # GET /api/v1/me/wins/:auction_id
        # @summary Show win details for current user
        # @response Win (200) [WonAuctionDetail]
        # @response Unauthorized (401) [Error]
        # @response Not found (404) [Error]
        def show
          result = Auctions::Queries::WonByUser.call(user: @current_user)
          settlement = result.records.find_by(auction_id: params[:auction_id])
          return render_error(code: :not_found, message: "Win not found", status: :not_found) unless settlement

          render json: Api::V1::WonAuctionDetailSerializer.new(settlement).as_json
        end
      end
    end
  end
end
