module Api
  module V1
    module Me
      class AccountController < ApplicationController
        before_action :authenticate_request!

        # GET /api/v1/me/account/profile
        # @summary Return current user's account profile (legacy /me alias)
        # @response Success (200) [AccountProfile]
        # @response Unauthorized (401) [Error]
        def profile
          user = @current_user
          render json: {
            user: {
              id: user.id,
              name: user.name,
              email_address: user.email_address,
              email_verified: user.email_verified?,
              email_verified_at: user.email_verified_at&.iso8601,
              created_at: user.created_at.iso8601,
              notification_preferences: user.notification_preferences_with_defaults
            }
          }, status: :ok
        end
      end
    end
  end
end
