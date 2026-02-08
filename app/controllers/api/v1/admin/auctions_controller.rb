module Api
  module V1
    module Admin
      class AuctionsController < BaseController
        ALLOWED_STATUSES = Auctions::Status.allowed_keys

        # GET /api/v1/admin/auctions
        # @summary List auctions for admin with filters and pagination
        # Returns auctions with optional status, date, and search filters for admin views.
        # @parameter status(query) [String] Filter by status (allowed: inactive, scheduled, active, complete, cancelled)
        # @parameter search(query) [String] Search by title or description
        # @parameter start_date_from(query) [String] ISO8601 lower bound for start date
        # @parameter start_date_to(query) [String] ISO8601 upper bound for start date
        # @parameter sort(query) [String] Sort column (e.g., start_date, end_time)
        # @parameter direction(query) [String] Sort direction (asc or desc)
        # @parameter page(query) [Integer] Page number for pagination
        # @parameter per_page(query) [Integer] Number of records per page
        # @response Admin auctions (200) [Array<Auction>]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def index
          result = ::Auctions::Queries::AdminIndex.call(params: admin_index_params)

          render json: result.records, each_serializer: Api::V1::Admin::AuctionSerializer, meta: result.meta
        end

        # GET /api/v1/admin/auctions/:id
        # @summary Show auction details for admin
        # Retrieves full auction details for administrators.
        # @parameter id(path) [Integer] ID of the auction
        # @response Auction found (200) [Auction]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        def show
          result = ::Auctions::Queries::AdminShow.call(params: { id: params[:id] })

          render json: result.record, serializer: Api::V1::Admin::AuctionSerializer
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Auction not found", status: :not_found)
        end

        # POST /api/v1/admin/auctions
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

        # PUT /api/v1/admin/auctions/:id
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

        # DELETE /api/v1/admin/auctions/:id
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

        # POST /api/v1/admin/auctions/:id/extend_time
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

        def admin_index_params
          params.permit(
            :status,
            :search,
            :start_date_from,
            :start_date_to,
            :sort,
            :direction,
            :page,
            :per_page
          )
        end

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
            :is_marketplace
          )
        end

        def normalized_auction_params
          attrs = auction_params.to_h
          return attrs unless attrs.key?("status")

          normalized = normalize_status(attrs["status"])
          return nil unless normalized

          attrs.merge!("status" => normalized)
        rescue ArgumentError
          nil
        end

        def normalize_status(raw_status)
          Auctions::Status.from_api(raw_status)
        end

        def render_invalid_status
          render_error(
            code: :invalid_status,
            message: "Invalid status. Allowed: #{ALLOWED_STATUSES.join(', ')}",
            status: :unprocessable_entity
          )
          nil
        end

        def render_service_error(result)
          render_error(code: result.code, message: result.message, status: result.http_status)
        end
      end
    end
  end
end
