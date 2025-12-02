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

        if user&.active?
          token, raw_token = PasswordResetToken.generate_for(user: user)
          deliver_email(user, raw_token)
          debug_token = Rails.env.production? ? nil : raw_token
          return render json: response_payload(debug_token), status: :accepted
        end

        render json: response_payload(nil), status: :accepted
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
        token = PasswordResetToken.find_valid_by_raw_token(reset_params[:token])
        return render json: { error: "Invalid or expired token" }, status: :unauthorized unless token

        user = token.user
        return render json: { error: "User account disabled" }, status: :forbidden if user.disabled?

        if user.update(password: reset_params[:password], password_confirmation: reset_params[:password_confirmation])
          token.mark_used!
          revoke_active_sessions(user)
          render json: { message: "Password updated" }, status: :ok
        else
          render json: { error: user.errors.full_messages.to_sentence }, status: :unprocessable_content
        end
      end

      private

      def forgot_params
        params.require(:password).permit(:email_address)
      end

      def reset_params
        params.require(:password).permit(:token, :password, :password_confirmation)
      end

      def handle_parameter_missing(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      def deliver_email(user, raw_token)
        PasswordMailer.reset_instructions(user, raw_token).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Failed to enqueue password reset email: #{e.message}")
      end

      def response_payload(debug_token)
        payload = { status: "ok" }
        payload[:debug_token] = debug_token if debug_token.present?
        payload
      end

      def revoke_active_sessions(user)
        user.session_tokens.active.find_each do |session_token|
          session_token.revoke!
          SessionEventBroadcaster.session_invalidated(session_token, reason: "password_reset")
        end
      end
    end
  end
end
