module Api
  module V1
    class AuctionsController < ApplicationController
      before_action :authenticate_request!, :authorize_admin!, only: [ :create, :update, :destroy, :extend_time ]

      ALLOWED_STATUSES = Auctions::Status.allowed_keys

      # @summary List all auctions
      # @no_auth
      def index
        result = ::Auctions::Queries::PublicIndex.new.call
        render json: result.records, each_serializer: Api::V1::AuctionSerializer
      end

      # @summary Retrieve a single auction with bids
      # @no_auth
      def show
        result = ::Auctions::Queries::PublicShow.new(id: params[:id]).call
        return render_error(code: :not_found, message: "Auction not found", status: :not_found) unless result.success?

        render json: result.record, include: :bids, serializer: Api::V1::AuctionSerializer
      end

      # @summary Create a new auction (admin only)
      def create
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = ::Admin::Auctions::Upsert.new(actor: @current_user, attrs: attrs, request: request).call
        return render_error(code: :invalid_auction, message: result.error, status: :unprocessable_entity) if result.error

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json, status: :created
      end

      # @summary Update an existing auction (admin only)
      def update
        auction = Auction.find(params[:id])
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = ::Admin::Auctions::Upsert.new(actor: @current_user, auction: auction, attrs: attrs, request: request).call
        return render_error(code: :invalid_auction, message: result.error, status: :unprocessable_entity) if result.error

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      # @summary Retire an auction (admin only)
      def destroy
        auction = Auction.find(params[:id])
        result = ::Admin::Auctions::Retire.new(actor: @current_user, auction: auction, request: request).call
        return render_error(code: :invalid_auction, message: result.error, status: :unprocessable_entity) if result.error

        head :no_content
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      # @summary Extend an auction's end time (admin only)
      def extend_time
        auction = Auction.find(params[:id])
        result = ::Admin::Auctions::Extend
          .new(actor: @current_user, auction: auction, window: 30.seconds, request: request)
          .call

        unless result.ok?
          status = case result.code
          when :forbidden then :forbidden
          when :invalid_state, :invalid_auction then :unprocessable_entity
          else :unprocessable_entity
          end
          return render_error(code: result.code, message: result.error, status: status)
        end

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
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
        render_error(code: :invalid_status, message: "Invalid status. Allowed: #{ALLOWED_STATUSES.join(', ')}", status: :unprocessable_entity)
        nil
      end
    end
  end
end
