module Api
  module V1
    class MaintenanceController < ApplicationController
      skip_before_action :authenticate_request!, raise: false

      # GET /api/v1/maintenance
      # @summary Show public maintenance mode state
      # Returns whether maintenance mode is enabled for end users.
      # @response Maintenance status (200) [Hash{ maintenance: Hash{ enabled: Boolean, updated_at: String } }]
      # @no_auth
      def show
        render json: Maintenance::Toggle.new(setting: MaintenanceSetting.global, cache: Rails.cache).payload
      end
    end
  end
end
