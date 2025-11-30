module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authenticate_request!, :authorize_superadmin!
        before_action :set_user, only: [:update]
        before_action :ensure_not_last_superadmin, only: [:update]

        # GET /api/v1/admin/users
        def index
          admins = User.where(role: [:admin, :superadmin])
          render json: admins
        end

        # PATCH/PUT /api/v1/admin/users/:id
        def update
          if @user.update(user_params)
            render json: @user
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def set_user
          @user = User.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "User not found" }, status: :not_found
        end

        def ensure_not_last_superadmin
          return unless @user.superadmin?
          requested_role = params.dig(:user, :role)
          return if requested_role.blank? || requested_role == "superadmin"

          remaining = User.superadmin.where.not(id: @user.id).exists?
          render json: { error: "Cannot remove the last superadmin" }, status: :forbidden unless remaining
        end

        def user_params
          params.require(:user).permit(:role, :name, :email_address)
        end
      end
    end
  end
end
