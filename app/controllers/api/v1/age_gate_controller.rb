module Api
  module V1
    class AgeGateController < ApplicationController
      before_action :authenticate_request!

      # POST /api/v1/age_gate/accept
      # Stores age-gate acceptance on the current session token.
      def accept
        @current_session_token.update!(age_verified_at: Time.current)
        head :no_content
      end
    end
  end
end
