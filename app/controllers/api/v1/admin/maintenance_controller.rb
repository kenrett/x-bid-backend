module Api
  module V1
    module Admin
      class MaintenanceController < ApplicationController
        before_action :authenticate_request!, :authorize_superadmin!

        # GET /api/v1/admin/maintenance
        # @summary Show current maintenance mode state
        # Returns the maintenance toggle state for administrators.
        # @response Maintenance status (200) [Hash{ maintenance: Hash{ enabled: Boolean, updated_at: String } }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def show
          render json: maintenance_payload
        end

        # POST /api/v1/admin/maintenance?enabled=true
        # Also accepts JSON body { enabled: true }
        # @summary Toggle maintenance mode on or off
        # Enables or disables maintenance mode.
        # @parameter enabled(query) [Boolean] Set to true to enable maintenance mode (optional if provided in body)
        # @request_body Maintenance toggle (application/json) [MaintenanceToggle]
        # @response Maintenance updated (200) [Hash{ maintenance: Hash{ enabled: Boolean, updated_at: String } }]
        # @response Bad request (400) [Error]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def update
          return render_error(code: :bad_request, message: "enabled param is required", status: :bad_request) if params[:enabled].nil?

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
