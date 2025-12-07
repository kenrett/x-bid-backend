module Api
  module V1
    module Admin
      class AuctionsController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!

        # GET /api/v1/admin/auctions
        # @summary List auctions for admin with filters and pagination
        def index
          result = ::Auctions::Queries::AdminIndex.call(params: admin_index_params)

          render json: result.records, each_serializer: Api::V1::Admin::AuctionSerializer, meta: result.meta
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
