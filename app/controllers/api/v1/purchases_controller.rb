module Api
  module V1
    class PurchasesController < ApplicationController
      before_action :authenticate_request!

      # GET /api/v1/purchases
      # @summary List current user's purchases (newest first)
      # @response Purchases (200) [Array<Purchase>]
      # @response Unauthorized (401) [Error]
      def index
        purchases = Payments::Queries::PurchasesForUser.call(user: @current_user).records

        # Use an explicit collection serializer + rootless adapter to avoid AMS root inference errors.
        render json: purchases, each_serializer: Api::V1::PurchaseSerializer, adapter: :attributes
      end

      # GET /api/v1/purchases/:id
      # @summary Show purchase details for current user
      # @response Purchase (200) [Purchase]
      # @response Unauthorized (401) [Error]
      # @response Not found (404) [Error]
      def show
        purchase = Purchase.includes(:bid_pack).find_by(id: params[:id], user_id: @current_user.id)
        return render_error(code: :not_found, message: "Purchase not found", status: :not_found) unless purchase

        render json: Api::V1::PurchaseSerializer.new(purchase).as_json
      end
    end
  end
end
