module Api
  module V1
    module Admin
      class BaseController < ApplicationController
        DEFAULT_PER_PAGE = 25
        MAX_PER_PAGE = 100
        before_action :authenticate_request!
        before_action :authorize_admin_role!
        before_action :enforce_admin_two_factor
        after_action :audit_admin_action

        private

        def required_role
          :admin
        end

        def authorize_admin_role!
          authorize!(required_role)
        end

        def enforce_admin_two_factor
          return unless require_admin_two_factor?
          return unless @current_user&.admin? || @current_user&.superadmin?
          unless @current_user.two_factor_enabled?
            return render_error(
              code: :two_factor_setup_required,
              message: "Two-factor authentication setup required",
              status: :forbidden
            )
          end

          return if @current_session_token&.two_factor_verified_at.present?

          render_error(code: :two_factor_required, message: "Two-factor authentication required", status: :unauthorized)
        end

        def require_admin_two_factor?
          ENV.fetch("REQUIRE_ADMIN_2FA", "true") == "true"
        end

        def audit_admin_action
          return unless @current_user
          return unless response.status < 400

          AuditLogger.log(
            action: "admin.#{controller_name}.#{action_name}",
            actor: @current_user,
            user: @current_user,
            request: request,
            payload: {
              target_type: audit_target_type,
              target_id: audit_target_id
            }.compact
          )
        end

        def audit_target_type
          return nil unless params[:id].present?

          controller_name.singularize.classify
        end

        def audit_target_id
          params[:id]
        end

        def page_number
          value = params[:page].to_i
          value.positive? ? value : 1
        end

        def per_page
          value = params[:per_page].to_i
          return DEFAULT_PER_PAGE if value <= 0

          [ value, MAX_PER_PAGE ].min
        end
      end
    end
  end
end
