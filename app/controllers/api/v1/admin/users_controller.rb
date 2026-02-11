module Api
  module V1
    module Admin
      class UsersController < BaseController
        before_action :set_user, except: [ :index ]
        before_action :ensure_superadmin_role_management!, only: [ :grant_admin, :revoke_admin, :grant_superadmin, :revoke_superadmin ]
        before_action :ensure_manageable_target!, only: [ :update, :ban ]
        before_action :ensure_not_last_superadmin_on_role_change, only: [ :update ]
        before_action :ensure_not_last_superadmin!, only: [ :revoke_superadmin, :ban ]

        # GET /api/v1/admin/users
        # @summary List manageable users
        # Returns users the current admin can manage.
        # @response Users (200) [Array<Hash{ id: Integer, name: String, email_address: String, role: String, status: String, email_verified: Boolean, email_verified_at: String }>]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def index
          users = manageable_users_scope.order(created_at: :desc)
          page_records = users.offset((page_number - 1) * per_page).limit(per_page + 1).to_a
          has_more = page_records.length > per_page
          records = page_records.first(per_page)
          serialized = ActiveModelSerializers::SerializableResource.new(
            records,
            each_serializer: AdminUserSerializer,
            adapter: :attributes
          ).as_json

          render json: { users: serialized, page: page_number, per_page: per_page, has_more: has_more }
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

          result = ::Admin::Users::GrantRole.new(
            actor: @current_user,
            user: @user,
            role: :admin,
            allow_superadmin_demotion: true,
            request: request
          ).call
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
          return render_error(code: result.code || :invalid_user, message: result.error, status: result.http_status) unless result.ok?

          render_admin_user(result.record)
        end

        # PATCH/PUT /api/v1/admin/users/:id
        # @summary Update a manageable user record
        # @parameter id(path) [Integer] ID of the user
        # @request_body Admin user payload (application/json) [AdminUserUpdate]
        # @response User updated (200) [Hash{ id: Integer, name: String, email_address: String, role: String, status: String, email_verified: Boolean, email_verified_at: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def update
          attrs = user_params
          return unless attrs

          if @user.update(attrs)
            AuditLogger.log(action: "user.update", actor: @current_user, target: @user, payload: attrs.to_h, request: request)
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
          raw = params.require(:user)
          permitted = raw.permit(:name, :email_address, :status, :email_verified, :email_verified_at)

          return nil unless normalize_status_param!(permitted)
          return nil unless normalize_email_verification_params!(raw, permitted)

          # Handle role explicitly to avoid broad mass assignment.
          if raw.key?(:role)
            unless @current_user.superadmin?
              render_error(code: :forbidden, message: "Superadmin privileges required", status: :forbidden)
              return nil
            end

            role_value = raw[:role].to_s
            unless User.roles.key?(role_value)
              render_error(code: :invalid_user, message: "Invalid role", status: :unprocessable_entity)
              return nil
            end

            permitted[:role] = role_value if User.roles.key?(role_value)
          end

          permitted.delete(:email_verified)
          permitted
        end

        def normalize_status_param!(permitted)
          return true unless permitted.key?(:status)

          normalized = normalize_user_status(permitted[:status].to_s)
          if User.statuses.key?(normalized)
            permitted[:status] = normalized
            return true
          end

          render_error(code: :invalid_user, message: "Invalid status. Allowed: active, disabled", status: :unprocessable_entity)
          false
        end

        def normalize_user_status(value)
          normalized = value.strip.downcase
          normalized = "disabled" if normalized.in?(%w[banned suspended])
          normalized
        end

        def normalize_email_verification_params!(raw, permitted)
          has_verified_flag = raw.key?(:email_verified)
          has_verified_at = raw.key?(:email_verified_at)

          if has_verified_flag
            verified = ActiveModel::Type::Boolean.new.cast(raw[:email_verified])
            permitted[:email_verified_at] = verified ? Time.current : nil unless has_verified_at
          end

          return true unless has_verified_at

          raw_verified_at = raw[:email_verified_at]
          permitted[:email_verified_at] =
            if raw_verified_at.blank?
              nil
            else
              parsed = Time.zone.parse(raw_verified_at.to_s)
              unless parsed
                render_error(code: :invalid_user, message: "Invalid email_verified_at datetime", status: :unprocessable_entity)
                return false
              end

              parsed
            end
          true
        end

        def ensure_manageable_target!
          return if @current_user.superadmin?
          return if @user&.user?

          render_error(code: :forbidden, message: "Admins can only moderate role=user accounts", status: :forbidden)
        end

        def ensure_superadmin_role_management!
          authorize!(:superadmin)
        end

        def manageable_users_scope
          return User.all if @current_user.superadmin?

          User.user
        end

        def render_admin_user(user)
          render json: user, serializer: AdminUserSerializer
        end

        def render_validation_error(user)
          render_error(code: :invalid_user, message: user.errors.full_messages.to_sentence, status: :unprocessable_entity)
        end
      end
    end
  end
end
