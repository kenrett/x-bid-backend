module Api
  module V1
    class AuctionsController < ApplicationController
      before_action :authenticate_request!, :authorize_admin!, only: [:create, :update, :destroy]
      resource_description do
        short 'Auction management'
        description 'Endpoints for viewing and managing auctions.'
      end

      ALLOWED_STATUSES = Auctions::Status.allowed_keys

      api :GET, '/auctions', 'List all auctions'
      error code: 200, desc: 'Success'
      error code: 401, desc: 'Unauthorized'
      error code: 403, desc: 'Admin privileges required'
      description 'Returns a list of all auctions. This endpoint is public.'
      def index
        auctions = Auction.includes(:winning_user).load
        render json: auctions, each_serializer: Api::V1::AuctionSerializer
      end

      api :GET, '/auctions/:id', 'Show a single auction'
      description 'Returns the details for a specific auction, including its bid history.'
      param :id, :number, desc: 'ID of the auction', required: true
      error code: 404, desc: 'Not Found'
      def show
        auction = Auction.includes(:bids, :winning_user).find(params[:id])
        render json: auction, include: :bids, serializer: Api::V1::AuctionSerializer
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Auction not found' }, status: :not_found
      end

      api :POST, "/auctions", "Create a new auction (admin only)"
      param :auction, Hash, required: true do
        param :title, String, required: true
        param :description, String, required: true
        param :image_url, String, required: false, default_value: nil
        param :status, String, required: false, default_value: nil
        param :start_date, String, desc: "ISO8601 datetime", required: true
        param :end_time, String, desc: "ISO8601 datetime", required: false, default_value: nil
        param :current_price, String, desc: "Price as string or numeric", required: true
        param :description, String
        param :image_url, String
        param :status, String
        param :start_date, String, desc: "ISO8601 datetime"
        param :end_time, String, desc: "ISO8601 datetime"
        param :current_price, String, desc: "Price as string or numeric"
      end
      error code: 200, desc: 'Success'
      error code: 401, desc: 'Unauthorized'
      error code: 403, desc: 'Admin privileges required'
      error code: 422, desc: 'Unprocessable content - validation errors or invalid status'
      def create
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = Auctions::AdminUpsert.new(actor: @current_user, attrs: attrs, request: request).call
        return render json: { error: result.error }, status: :unprocessable_content if result.error

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json, status: :created
      end

      api :PUT, "/auctions/:id", "Update an auction (admin only)"
      param :id, :number, desc: "Auction ID", required: true
      error code: 204, desc: 'Deleted'
      error code: 401, desc: 'Unauthorized'
      error code: 403, desc: 'Admin privileges required'
      error code: 404, desc: 'Not found'
      error code: 422, desc: 'Unprocessable content - validation errors or invalid status'
      def update
        auction = Auction.find(params[:id])
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = Auctions::AdminUpsert.new(actor: @current_user, auction: auction, attrs: attrs, request: request).call
        return render json: { error: result.error }, status: :unprocessable_content if result.error

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Auction not found" }, status: :not_found
      end

      api :DELETE, "/auctions/:id", "Delete an auction (admin only)"
      param :id, :number, desc: "Auction ID", required: true
      error code: 401, desc: 'Unauthorized'
      error code: 403, desc: 'Admin privileges required'
      error code: 404, desc: 'Not found'
      error code: 422, desc: 'Unprocessable content - cannot delete auction with bids'
      def destroy
        auction = Auction.find(params[:id])
        result = Auctions::Retire.new(actor: @current_user, auction: auction, request: request).call
        return render json: { error: result.error }, status: :unprocessable_content if result.error

        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Auction not found" }, status: :not_found
      end

      private

      def auction_params
        params.require(:auction).permit(
          :title,
          :description,
          :image_url,
          :status,
          :start_date,
          :end_time,
          :current_price
        )
      end

      def normalized_auction_params
        attrs = auction_params.to_h
        return attrs unless attrs.key?("status")

        normalized = normalize_status(attrs["status"])
        return nil unless normalized

        attrs.merge!("status" => normalized)
      rescue ArgumentError => e
        # Log the error if you want, e.g. Rails.logger.error(e.message)
        nil
      end

      def normalize_status(raw_status)
        Auctions::Status.from_api(raw_status)
      end

    def render_invalid_status
      render json: { error: "Invalid status. Allowed: #{ALLOWED_STATUSES.join(', ')}" }, status: :unprocessable_content
      nil
    end
  end
end
end
