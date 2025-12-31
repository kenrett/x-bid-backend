module Api
  module V1
    class AccountPasswordsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/account/password
      # @summary Change password for the current user
      # Revokes all other active sessions on success.
      # @request_body Change password payload (application/json) [!ChangePasswordRequest]
      # @response Success (200) [Hash{ status: String, sessions_revoked: Integer }]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      def create
        result = Account::ChangePassword.new(
          user: @current_user,
          current_session_token: @current_session_token,
          current_password: password_params.fetch(:current_password),
          new_password: password_params.fetch(:new_password)
        ).call

        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "password_updated", sessions_revoked: result.sessions_revoked }, status: :ok
      end

      private

      def password_params
        (params[:password].presence || params).permit(:current_password, :new_password)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
