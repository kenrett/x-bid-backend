module Api
  module V1
    module Admin
      class AuditController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!

        # POST /api/v1/admin/audit
        def create
          log = AuditLogger.log(
            action: audit_params[:action],
            actor: @current_user,
            target: audit_target,
            payload: audit_params[:payload],
            request: request
          )

          if log
            render json: { status: "ok" }, status: :created
          else
            render json: { error: "Unable to create audit log" }, status: :unprocessable_content
          end
        end

        private

        def audit_params
          params.require(:audit).permit(:action, :target_type, :target_id, payload: {})
        end

        def audit_target
          return nil unless audit_params[:target_type].present? && audit_params[:target_id].present?

          audit_params[:target_type].constantize.find(audit_params[:target_id])
        rescue NameError, ActiveRecord::RecordNotFound
          nil
        end
      end
    end
  end
end
