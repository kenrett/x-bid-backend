module Api
  module V1
    class MaintenanceController < ApplicationController
      skip_before_action :authenticate_request!, raise: false

      # GET /api/v1/maintenance
      # @summary Show public maintenance mode state
      # @no_auth
      def show
        render json: Maintenance::Toggle.new(setting: MaintenanceSetting.global, cache: Rails.cache).payload
      end
    end
  end
end
