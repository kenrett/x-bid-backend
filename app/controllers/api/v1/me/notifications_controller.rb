module Api
  module V1
    module Me
      class NotificationsController < ApplicationController
        before_action :authenticate_request!

        # GET /api/v1/me/notifications
        # @summary List current user's notifications (newest first)
        # @response Notifications (200) [Array<Notification>]
        # @response Unauthorized (401) [Error]
        def index
          result = Notifications::Queries::ForUser.call(user: @current_user)
          render json: result.records, each_serializer: Api::V1::NotificationSerializer, adapter: :attributes
        end
      end
    end
  end
end
