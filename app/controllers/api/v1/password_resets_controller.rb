module Api
  module V1
    class PasswordResetsController < ApplicationController
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # @summary Request a password reset email
      # @response Accepted (202) [Hash{ status: String }]
      # @response Bad request (400) [Error]
      # @no_auth
      def create
        user = User.find_by(email_address: forgot_params[:email_address])
        result = Auth::PasswordReset.new(user: user, reset_params: {}, environment: Rails.env).request_reset
        render json: response_payload(result.debug_token), status: :accepted
      end

      # @summary Reset a password using a token
      # @response Password reset (200) [Hash{ message: String }]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Validation error (422) [Error]
      # @response Bad request (400) [Error]
      # @no_auth
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
