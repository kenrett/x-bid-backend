module Api
  module V1
    class AccountController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # GET /api/v1/account
      # @summary Return current account profile
      # @response Success (200) [AccountProfile]
      # @response Unauthorized (401) [Error]
      def show
        render json: build_account_payload(@current_user), status: :ok
      end

      # PATCH /api/v1/account
      # @summary Update account profile (MVP: name only)
      # @request_body Update payload (application/json) [!AccountUpdateRequest]
      # @response Updated (200) [AccountProfile]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      def update
        name = account_params.fetch(:name)
        result = Account::UpdateProfile.new(user: @current_user, name: name).call
        return render_error(code: result.code || :validation_error, message: result.message, status: result.http_status) unless result.ok?

        render json: build_account_payload(result.user), status: :ok
      end

      private

      def build_account_payload(user)
        {
          user: {
            id: user.id,
            name: user.name,
            email_address: user.email_address,
            email_verified: user.email_verified?,
            email_verified_at: user.email_verified_at&.iso8601,
            created_at: user.created_at.iso8601,
            notification_preferences: user.notification_preferences_with_defaults
          }
        }
      end

      def account_params
        params.require(:account).permit(:name)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
