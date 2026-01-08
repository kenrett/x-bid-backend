module Api
  module V1
    class AgeGateController < ApplicationController
      before_action :authenticate_request!

      # POST /api/v1/age_gate/accept
      # @summary Accept 18+ age gate for the current session
      # Stores age-gate acceptance on the current session token.
      # @response Accepted (204) [Hash{}]
      # @response Unauthorized (401) [Error]
      def accept
        @current_session_token.update!(age_verified_at: Time.current)
        head :no_content
      end
    end
  end
end
