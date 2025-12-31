module Api
  module V1
    class AccountNotificationsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # GET /api/v1/account/notifications
      # @summary Return notification preferences for the current user
      # @response Success (200) [NotificationPreferencesResponse]
      # @response Unauthorized (401) [Error]
      def show
        render json: { notification_preferences: @current_user.notification_preferences_with_defaults }, status: :ok
      end

      # PATCH /api/v1/account/notifications
      # @summary Update notification preferences for the current user
      # @request_body Update preferences payload (application/json) [!NotificationPreferencesUpdateRequest]
      # @response Success (200) [NotificationPreferencesResponse]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      def update
        prefs = notification_params.fetch(:notification_preferences).to_h
        result = Account::UpdateNotificationPreferences.new(user: @current_user, preferences: prefs).call
        return render_error(code: result.code, message: result.message, status: result.http_status, details: result.details) unless result.ok?

        render json: { notification_preferences: result.notification_preferences }, status: :ok
      end

      private

      def notification_params
        params.require(:account).permit(notification_preferences: {})
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
