module Api
  module V1
    class AuctionsController < ApplicationController
      before_action :authenticate_request!, :authorize_admin!, only: [:create, :update, :destroy]
      resource_description do
        short 'Auction management'
        description 'Endpoints for viewing and managing auctions.'
      end

      ALLOWED_STATUSES = %w[inactive scheduled active complete cancelled].freeze

      api :GET, '/auctions', 'List all auctions'
      error code: 200, desc: 'Success'
      error code: 401, desc: 'Unauthorized'
      error code: 403, desc: 'Admin privileges required'
      description 'Returns a list of all auctions. This endpoint is public.'
      def index
        auctions = Auction.all
        auctions = Auction.with_attached_image # Or whatever scope is appropriate
        render json: auctions
      end

      api :GET, '/auctions/:id', 'Show a single auction'
      description 'Returns the details for a specific auction, including its bid history.'
      param :id, :number, desc: 'ID of the auction', required: true
      error code: 404, desc: 'Not Found'
      def show
        auction = Auction.includes(:bids).find(params[:id])
        render json: auction, include: :bids
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

        auction = Auction.new(attrs)
        if auction.save
          AuditLogger.log(action: "auction.create", actor: @current_user, target: auction, payload: attrs)
          render json: auction, status: :created
        else
          render json: { errors: auction.errors.full_messages }, status: :unprocessable_content
        end
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

        if auction.update(attrs)
          AuditLogger.log(action: "auction.update", actor: @current_user, target: auction, payload: attrs)
          render json: auction
        else
          render json: { errors: auction.errors.full_messages }, status: :unprocessable_content
        end
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
        if auction.inactive?
          return render json: { error: "Auction already inactive" }, status: :unprocessable_content
        end

        if auction.bids.exists?
          return render json: { error: "Cannot retire an auction that has bids." }, status: :unprocessable_content
        end

        if auction.update(status: :inactive)
          AuditLogger.log(action: "auction.delete", actor: @current_user, target: auction, payload: { status: "inactive" })
          head :no_content
        else
          render json: { error: auction.errors.full_messages.to_sentence }, status: :unprocessable_content
        end
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
        return if raw_status.blank?

        status_key = raw_status.to_s.downcase
        mapping = {
          "inactive" => "inactive",
          "scheduled" => "pending",
          "active" => "active",
          "complete" => "ended",
          "cancelled" => "cancelled"
        }
        mapping[status_key]
      end

      def render_invalid_status
        render json: { error: "Invalid status. Allowed: #{ALLOWED_STATUSES.join(', ')}" }, status: :unprocessable_content
        nil
      end
    end
  end
end
