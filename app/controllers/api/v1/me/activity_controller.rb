module Api
  module V1
    module Me
      class ActivityController < ApplicationController
        before_action :authenticate_request!

        # GET /api/v1/me/activity
        # @summary List current user's activity feed
        # Returns an event-backed, newest-first feed with cursor pagination.
        def index
          result = Activity::Queries::FeedForUser.call(user: @current_user, params: activity_params)

          render json: {
            items: result.records,
            page: result.meta.fetch(:page),
            per_page: result.meta.fetch(:per_page),
            has_more: result.meta.fetch(:has_more),
            next_cursor: result.meta.fetch(:next_cursor)
          }
        rescue ArgumentError => e
          render_error(code: :invalid_cursor, message: e.message, status: :bad_request)
        end

        private

        def activity_params
          params.permit(:page, :per_page, :cursor)
        end
      end
    end
  end
end
