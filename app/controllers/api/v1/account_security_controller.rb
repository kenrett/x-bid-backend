module Api
  module V1
    class AccountSecurityController < ApplicationController
      before_action :authenticate_request!

      # GET /api/v1/account/security
      # @summary Return account security fields (email verification)
      # @response Success (200) [AccountSecurity]
      # @response Unauthorized (401) [Error]
      def show
        render json: {
          security: {
            email_address: @current_user.email_address,
            unverified_email_address: @current_user.unverified_email_address,
            email_verified: @current_user.email_verified?,
            email_verified_at: @current_user.email_verified_at&.iso8601,
            email_verification_sent_at: @current_user.email_verification_sent_at&.iso8601
          }
        }, status: :ok
      end
    end
  end
end
