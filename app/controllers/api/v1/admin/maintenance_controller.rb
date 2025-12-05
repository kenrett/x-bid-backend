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

        enabled = Maintenance::Toggle.new(setting: MaintenanceSetting.global, cache: Rails.cache).update(enabled: params[:enabled])

        AuditLogger.log(action: "maintenance.update", actor: @current_user, payload: { enabled: enabled }, request: request)

        render json: maintenance_payload
      end

      private

      def maintenance_payload
        Maintenance::Toggle.new(setting: MaintenanceSetting.global, cache: Rails.cache).payload
      end
      end
    end
  end
end
