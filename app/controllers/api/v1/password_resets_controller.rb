module Api
  module V1
    class PasswordResetsController < ApplicationController
      resource_description do
        short "Password reset"
      end

      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      api :POST, "/password/forgot", "Request a password reset email"
      param :password, Hash, required: true do
        param :email_address, String, desc: "Email for the account", required: true
      end
      error code: 202, desc: "Accepted (always, to prevent account enumeration)"
      def create
        user = User.find_by(email_address: forgot_params[:email_address])
        result = Auth::PasswordReset.new(user: user, reset_params: {}, environment: Rails.env).request_reset
        render json: response_payload(result.debug_token), status: :accepted
      end

      api :POST, "/password/reset", "Reset password using the reset token"
      param :password, Hash, required: true do
        param :token, String, desc: "Reset token from email", required: true
        param :password, String, desc: "New password", required: true
        param :password_confirmation, String, desc: "New password confirmation", required: true
      end
      error code: 401, desc: "Invalid or expired token"
      error code: 403, desc: "User account disabled"
      error code: 422, desc: "Validation errors on password update"
      def update
        user = nil
        result = Auth::PasswordReset.new(user: user, reset_params: reset_params, environment: Rails.env).reset_password

        return render_error(code: :invalid_token, message: result.error, status: :unauthorized) if result.error == "Invalid or expired token"
        return render_error(code: :account_disabled, message: result.error, status: :forbidden) if result.error == "User account disabled"
        return render_error(code: :invalid_password, message: result.error, status: :unprocessable_entity) if result.error

        render json: { message: result.message }, status: :ok
      end

      private

      def forgot_params
        params.require(:password).permit(:email_address)
      end

      def reset_params
        params.require(:password).permit(:token, :password, :password_confirmation)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end

      def response_payload(debug_token)
        payload = { status: "ok" }
        payload[:debug_token] = debug_token if debug_token.present?
        payload
      end
    end
  end
end
