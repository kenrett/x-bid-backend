module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authenticate_request!, :authorize_superadmin!
        before_action :set_user, except: [:index]
        before_action :ensure_not_last_superadmin_on_role_change, only: [:update]
        before_action :ensure_not_last_superadmin!, only: [:revoke_superadmin, :ban]

        # GET /api/v1/admin/users
        def index
          admins = User.where(role: [:admin, :superadmin])
          render json: admins, each_serializer: AdminUserSerializer
        end

        def grant_admin
          return render_error("User is already a superadmin") if @user.superadmin?
          return render_error("User is already an admin") if @user.admin?

          if @user.update(role: :admin)
            AuditLogger.log(action: "user.grant_admin", actor: @current_user, target: @user)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        def revoke_admin
          return render_error("Cannot revoke admin from a superadmin", :forbidden) if @user.superadmin?
          return render_error("User is not an admin") unless @user.admin?

          if @user.update(role: :user)
            AuditLogger.log(action: "user.revoke_admin", actor: @current_user, target: @user)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        def grant_superadmin
          return render_error("User is already a superadmin") if @user.superadmin?

          if @user.update(role: :superadmin)
            AuditLogger.log(action: "user.grant_superadmin", actor: @current_user, target: @user)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        def revoke_superadmin
          return render_error("User is not a superadmin") unless @user.superadmin?

          if @user.update(role: :admin)
            AuditLogger.log(action: "user.revoke_superadmin", actor: @current_user, target: @user)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        def ban
          return render_error("User already disabled") if @user.disabled?

          @user.disable_and_revoke_sessions!
          AuditLogger.log(action: "user.ban", actor: @current_user, target: @user)
          render_admin_user(@user)
        rescue ActiveRecord::ActiveRecordError => e
          render_error("Unable to disable user: #{e.message}")
        end

        # PATCH/PUT /api/v1/admin/users/:id
        def update
          if @user.update(user_params)
            AuditLogger.log(action: "user.update", actor: @current_user, target: @user, payload: user_params.to_h)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        private

        def set_user
          @user = User.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("User not found", :not_found)
        end

        def ensure_not_last_superadmin_on_role_change
          return unless @user&.superadmin?
          requested_role = params.dig(:user, :role)
          return if requested_role.blank? || requested_role == "superadmin"

          remaining = User.superadmin.where.not(id: @user.id).exists?
          render_error("Cannot remove the last superadmin", :forbidden) unless remaining
        end

        def ensure_not_last_superadmin!
          return unless @user&.superadmin?

          remaining = User.superadmin.where.not(id: @user.id).exists?
          render_error("Cannot remove the last superadmin", :forbidden) unless remaining
        end

        def user_params
          params.require(:user).permit(:role, :name, :email_address)
        end

        def render_admin_user(user)
          render json: user, serializer: AdminUserSerializer
        end

        def render_error(message, status = :unprocessable_content)
          render json: { error: message }, status: status
        end

        def render_validation_error(user)
          render_error(user.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
