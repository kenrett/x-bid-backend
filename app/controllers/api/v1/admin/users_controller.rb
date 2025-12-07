module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authenticate_request!, :authorize_superadmin!
        before_action :set_user, except: [ :index ]
        before_action :ensure_not_last_superadmin_on_role_change, only: [ :update ]
        before_action :ensure_not_last_superadmin!, only: [ :revoke_superadmin, :ban ]

        # GET /api/v1/admin/users
        # @summary List admin and superadmin users
        # Returns the list of administrative users.
        # @response Admin users (200) [Array<Hash{ id: Integer, name: String, email_address: String, role: String }>]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def index
          admins = User.where(role: [ :admin, :superadmin ])
          render json: admins, each_serializer: AdminUserSerializer, adapter: :attributes
        end

        # @summary Grant admin role to a user
        # @parameter id(path) [Integer] ID of the user
        # @response Role updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def grant_admin
          result = ::Admin::Users::GrantRole.new(actor: @current_user, user: @user, role: :admin, request: request).call
          return render_error(code: :invalid_user, message: result.error, status: :unprocessable_entity) if result.error
          render_admin_user(result.user)
        end

        # @summary Revoke admin role from a user
        # @parameter id(path) [Integer] ID of the user
        # @response Role updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def revoke_admin
          return render_error(code: :forbidden, message: "Cannot revoke admin from a superadmin", status: :forbidden) if @user.superadmin?
          return render_error(code: :invalid_user, message: "User is not an admin", status: :unprocessable_entity) unless @user.admin?

          result = ::Admin::Users::GrantRole.new(actor: @current_user, user: @user, role: :user, request: request).call
          return render_error(code: :invalid_user, message: result.error, status: :unprocessable_entity) if result.error
          render_admin_user(result.user)
        end

        # @summary Grant superadmin role to a user
        # @parameter id(path) [Integer] ID of the user
        # @response Role updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def grant_superadmin
          result = ::Admin::Users::GrantRole.new(actor: @current_user, user: @user, role: :superadmin, request: request).call
          return render_error(code: :invalid_user, message: result.error, status: :unprocessable_entity) if result.error
          render_admin_user(result.user)
        end

        # @summary Revoke superadmin role from a user
        # @parameter id(path) [Integer] ID of the user
        # @response Role updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def revoke_superadmin
          return render_error(code: :invalid_user, message: "User is not a superadmin", status: :unprocessable_entity) unless @user.superadmin?

          result = ::Admin::Users::GrantRole.new(actor: @current_user, user: @user, role: :admin, request: request).call
          return render_error(code: :invalid_user, message: result.error, status: :unprocessable_entity) if result.error
          render_admin_user(result.user)
        end

        # @summary Ban a user account
        # @parameter id(path) [Integer] ID of the user
        # @response User banned (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def ban
          result = ::Admin::Users::Disable.new(actor: @current_user, user: @user, request: request).call
          return render_error(code: result.code || :invalid_user, message: result.error, status: map_status(result.code)) unless result.ok?

          render_admin_user(result.record)
        end

        # PATCH/PUT /api/v1/admin/users/:id
        # @summary Update an admin/superadmin user record
        # @parameter id(path) [Integer] ID of the user
        # @request_body Admin user payload (application/json) [AdminUserUpdate]
        # @response User updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def update
          if @user.update(user_params)
            AuditLogger.log(action: "user.update", actor: @current_user, target: @user, payload: user_params.to_h, request: request)
            render_admin_user(@user)
          else
            render_validation_error(@user)
          end
        end

        private

        def set_user
          @user = User.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "User not found", status: :not_found)
        end

        def ensure_not_last_superadmin_on_role_change
          return unless @user&.superadmin?
          requested_role = params.dig(:user, :role)
          return if requested_role.blank? || requested_role == "superadmin"

          remaining = User.superadmin.where.not(id: @user.id).exists?
          render_error(code: :forbidden, message: "Cannot remove the last superadmin", status: :forbidden) unless remaining
        end

        def ensure_not_last_superadmin!
          return unless @user&.superadmin?

          remaining = User.superadmin.where.not(id: @user.id).exists?
          render_error(code: :forbidden, message: "Cannot remove the last superadmin", status: :forbidden) unless remaining
        end

        def user_params
          permitted = params.require(:user).permit(:name, :email_address)

          # Handle role explicitly to avoid broad mass assignment.
          if params[:user].present? && params[:user].key?(:role)
            role_value = params[:user][:role].to_s
            permitted[:role] = role_value if User.roles.key?(role_value)
          end

          permitted
        end

        def render_admin_user(user)
          render json: user, serializer: AdminUserSerializer
        end

        def render_validation_error(user)
          render_error(code: :invalid_user, message: user.errors.full_messages.to_sentence, status: :unprocessable_entity)
        end

        def map_status(code)
          case code
          when :forbidden then :forbidden
          when :invalid_delta, :invalid_user, :insufficient_credits then :unprocessable_content
          else :unprocessable_entity
          end
        end
      end
    end
  end
end
