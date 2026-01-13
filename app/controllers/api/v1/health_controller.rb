module Api
  module V1
    class HealthController < ApplicationController
      def show
        render json: { status: "ok", request_id: request.request_id }
      end
    end
  end
end
