module Api
  module V1
    module Admin
      class AuctionsController < ApplicationController
        before_action :authenticate_request!
        before_action -> { authorize!(:admin) }

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
      end
    end
  end
end
