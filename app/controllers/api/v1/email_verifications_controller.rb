module Api
  module V1
    class EmailVerificationsController < ApplicationController
      before_action :authenticate_request!, only: [ :resend ]
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/email_verifications/resend
      # @summary Resend verification email for the current user
      # @response Accepted (202) [Hash{ status: String }]
      # @response Unauthorized (401) [Error]
      # @response Too many requests (429) [Error]
      def resend
        result = Account::ResendEmailVerification.new(user: @current_user, environment: Rails.env).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "verification_sent" }, status: :accepted
      end

      # GET /api/v1/email_verifications/verify
      # @summary Verify an email verification token
      # @parameter token(query) [String] Email verification token
      # @response Success (200) [Hash{ status: String }]
      # @response Unprocessable content (422) [Error]
      # @no_auth
      def verify
        token = params.fetch(:token)
        result = Account::VerifyEmail.new(raw_token: token).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "verified" }, status: :ok
      end

      private

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
