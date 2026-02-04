module Api
  module V1
    class AuctionsController < ApplicationController
      before_action :authenticate_request!, only: [ :create, :update, :destroy, :extend_time ]
      before_action -> { authorize!(:admin) }, only: [ :create, :update, :destroy, :extend_time ]

      ALLOWED_STATUSES = Auctions::Status.allowed_keys

      # @summary List all auctions
      # Returns public auction summaries filtered by status.
      # @parameter status(query) [String] Filter by status (allowed: inactive, scheduled, active, complete, cancelled)
      # @response Auctions (200) [Array<AuctionSummary>]
      # @response Validation error (422) [Error]
      # @no_auth
      def index
        storefront_key = Current.storefront_key
        scoped = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: storefront_key)
        vary_on_storefront_key!

        ttl = public_index_cache_ttl
        expires_in ttl, public: true, must_revalidate: true, "s-maxage": ttl.to_i, stale_while_revalidate: public_index_swr

        last_modified = Auction.maximum(:updated_at)&.utc || Time.at(0).utc
        etag = [ "auctions-index", storefront_key.to_s, params[:status].to_s, last_modified.to_i, Auction.count ]
        return unless stale?(etag: etag, last_modified: last_modified, public: true)

        result = ::Auctions::Queries::PublicIndex.call(params: public_index_params, relation: scoped)
        auctions = ActiveModelSerializers::SerializableResource.new(
          result.records,
          each_serializer: Api::V1::AuctionSerializer,
          root: false
        ).as_json
        render json: { auctions: auctions }
      end

      # @summary Retrieve a single auction with bids
      # Fetches the auction and embeds the current bid list.
      # @parameter id(path) [Integer] ID of the auction
      # @response Auction found (200) [Auction]
      # @response Not found (404) [Error]
      # @no_auth
      def show
        storefront_key = Current.storefront_key
        scoped = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: storefront_key)
        vary_on_storefront_key!

        auction = scoped.select(:id, :status, :updated_at, :is_adult, :is_artisan).find(params[:id])
        unless Storefront::Policy.can_view_artisan_detail?(storefront_key: storefront_key, auction: auction)
          raise ActiveRecord::RecordNotFound
        end

        if Storefront::Policy.adult_detail?(auction)
          session_token = Auth::OptionalSession.session_token_from_request(request)
          unless Storefront::Policy.can_view_adult_detail?(storefront_key: storefront_key, session_token: session_token, auction: auction)
            expires_now
            response.headers["Cache-Control"] = "no-store"
            return render_error(
              code: "AGE_GATE_REQUIRED",
              message: "Age gate acceptance required to view this item.",
              status: :forbidden
            )
          end

          expires_now
          response.headers["Cache-Control"] = "no-store"
          result = ::Auctions::Queries::PublicShow.call(params: { id: params[:id] }, relation: scoped)
          return render json: result.record, include: :bids, serializer: Api::V1::AuctionSerializer
        end

        ttl = public_show_cache_ttl(auction)
        expires_in ttl, public: true, must_revalidate: true, "s-maxage": ttl.to_i, stale_while_revalidate: public_show_swr(ttl)

        last_modified = auction.updated_at&.utc || Time.at(0).utc
        etag = [ "auctions-show", storefront_key.to_s, auction.id, auction.status, last_modified.to_i ]
        return unless stale?(etag: etag, last_modified: last_modified, public: true)

        result = ::Auctions::Queries::PublicShow.call(params: { id: params[:id] }, relation: scoped)
        render json: result.record, include: :bids, serializer: Api::V1::AuctionSerializer
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      # @summary Create a new auction (admin only)
      # Create and schedule or activate an auction. Status values are normalized to the allowed list.
      # @request_body Auction payload (application/json) [!AuctionUpsert]
      # @response Auction created (201) [Auction]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Validation error (422) [Error]
      def create
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = ::Admin::Auctions::Upsert.new(actor: @current_user, attrs: attrs, request: request).call
        return render_service_error(result) unless result.ok?

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json, status: :created
      end

      # @summary Update an existing auction (admin only)
      # Update auction details or transition status for an existing auction.
      # @parameter id(path) [Integer] ID of the auction
      # @request_body Auction payload (application/json) [!AuctionUpsert]
      # @response Auction updated (200) [Auction]
      # @response Unauthorized (401) [Error]
      # @response Not found (404) [Error]
      # @response Forbidden (403) [Error]
      # @response Validation error (422) [Error]
      def update
        auction = Auction.find(params[:id])
        attrs = normalized_auction_params
        return render_invalid_status unless attrs

        result = ::Admin::Auctions::Upsert.new(actor: @current_user, auction: auction, attrs: attrs, request: request).call
        return render_service_error(result) unless result.ok?

        render json: Api::V1::Admin::AuctionSerializer.new(result.record).as_json
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      # @summary Retire an auction (admin only)
      # Retire an auction to prevent further bids while keeping history intact.
      # @parameter id(path) [Integer] ID of the auction
      # @response Auction retired (204) [Hash{}]
      # @response Unauthorized (401) [Error]
      # @response Not found (404) [Error]
      # @response Forbidden (403) [Error]
      # @response Validation error (422) [Error]
      def destroy
        auction = Auction.find(params[:id])
        result = ::Admin::Auctions::Retire.new(actor: @current_user, auction: auction, request: request).call
        return render_service_error(result) unless result.ok?

        head :no_content
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      # @summary Extend an auction's end time (admin only)
      # Extends an active auction within the configured extension window.
      # @parameter id(path) [Integer] ID of the auction
      # @response Auction extended (200) [Auction]
      # @response Unauthorized (401) [Error]
      # @response Not found (404) [Error]
      # @response Forbidden (403) [Error]
      # @response Validation error (422) [Error]
      def extend_time
        auction = Auction.find(params[:id])
        result = ::Admin::Auctions::Extend
          .new(actor: @current_user, auction: auction, window: 30.seconds, request: request)
          .call

        return render_service_error(result) unless result.ok?

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
          :current_price,
          :is_adult,
          :is_artisan
        )
      end

      def vary_on_storefront_key!
        vary = response.headers["Vary"].to_s
        return response.headers["Vary"] = "X-Storefront-Key" if vary.blank?
        return if vary.split(",").map(&:strip).include?("X-Storefront-Key")

        response.headers["Vary"] = "#{vary}, X-Storefront-Key"
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

      def render_service_error(result)
        render_error(code: result.code, message: result.message, status: result.http_status)
      end

      def public_index_params
        params.permit(:status)
      end

      def public_index_cache_ttl
        case params[:status].to_s
        when "active"
          2.seconds
        when "scheduled", "pending"
          10.seconds
        when "inactive"
          60.seconds
        when "complete", "ended", "cancelled"
          5.minutes
        else
          2.seconds
        end
      end

      def public_index_swr
        [ public_index_cache_ttl * 5, 5.minutes ].min
      end

      def public_show_cache_ttl(auction)
        if auction.status.to_s == "active"
          2.seconds
        else
          60.seconds
        end
      end

      def public_show_swr(ttl)
        [ ttl * 5, 5.minutes ].min
      end
    end
  end
end
