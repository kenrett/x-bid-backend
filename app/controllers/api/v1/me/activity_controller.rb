module Api
  module V1
    module Me
      class ActivityController < ApplicationController
        before_action :authenticate_request!

        # GET /api/v1/me/activity
        # @summary List current user's activity feed
        # Merges bids, watches, and outcomes into a single newest-first feed.
        # NOTE: Currently merges in Ruby; may not scale for large histories.
        def index
          result = Activity::Queries::FeedForUser.call(user: @current_user, params: activity_params)

          render json: {
            items: result.records,
            page: result.meta.fetch(:page),
            per_page: result.meta.fetch(:per_page),
            has_more: result.meta.fetch(:has_more)
          }
        end

        private

        def activity_params
          params.permit(:page, :per_page)
        end
      end
    end
  end
end
