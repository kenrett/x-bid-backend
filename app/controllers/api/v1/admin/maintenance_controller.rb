module Api
  module V1
    module Admin
      class MaintenanceController < ApplicationController
        before_action :authenticate_request!, :authorize_superadmin!

        # GET /api/v1/admin/maintenance
        def show
          render json: maintenance_payload
        end

        # POST /api/v1/admin/maintenance?enabled=true
        # Also accepts JSON body { enabled: true }
        def update
          return render json: { error: "enabled param is required" }, status: :bad_request if params[:enabled].nil?

          enabled = ActiveRecord::Type::Boolean.new.cast(params[:enabled])
          MaintenanceSetting.global.update!(enabled: enabled)
          Rails.cache.write(cache_key(:enabled), enabled)
          Rails.cache.write(cache_key(:updated_at), Time.current.iso8601)

          AuditLogger.log(action: "maintenance.update", actor: @current_user, payload: { enabled: enabled }, request: request)

          render json: maintenance_payload
        end

        private

        def maintenance_payload
          enabled = Rails.cache.read(cache_key(:enabled))
          enabled = MaintenanceSetting.global.enabled if enabled.nil?

          {
            maintenance: {
              enabled: enabled,
              updated_at: Rails.cache.read(cache_key(:updated_at)) || MaintenanceSetting.global.updated_at&.iso8601
            }
          }
        end

        def cache_key(suffix)
          "maintenance_mode.#{suffix}"
        end
      end
    end
  end
end
