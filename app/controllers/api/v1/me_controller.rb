module Api
  module V1
    class MeController < ApplicationController
      before_action :authenticate_request!

      # GET /api/v1/me
      # @summary Return the authenticated user
      # @response Current user (200) [Hash{ user: Hash }]
      # @response Unauthorized (401) [Error]
      def show
        render json: { user: Auth::SessionResponseBuilder.user_data(@current_user) }, status: :ok
      end
    end
  end
end
