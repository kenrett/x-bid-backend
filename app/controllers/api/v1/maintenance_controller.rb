module Api
  module V1
    class MaintenanceController < ApplicationController
      skip_before_action :authenticate_request!, raise: false

      # GET /api/v1/maintenance
      def show
        render json: {
          maintenance: {
            enabled: maintenance_enabled?,
            updated_at: maintenance_updated_at
          }
        }
      end

      private

      def maintenance_updated_at
        Rails.cache.read("maintenance_mode.updated_at") || MaintenanceSetting.global.updated_at&.iso8601
      end
    end
  end
end
