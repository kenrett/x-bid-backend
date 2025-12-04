module Admin
  module Users
    class GrantRole
      Result = Struct.new(:user, :error, keyword_init: true)

      def initialize(actor:, user:, role:, request: nil)
        @actor = actor
        @user = user
        @role = role.to_sym
        @request = request
      end

      def call
        return Result.new(error: "User is already a superadmin") if superadmin_conflict?
        return Result.new(error: "User is already an admin") if admin_conflict?

        if @user.update(role: @role)
          AuditLogger.log(action: action_name, actor: @actor, target: @user, request: @request)
          Result.new(user: @user)
        else
          Result.new(error: @user.errors.full_messages.to_sentence)
        end
      end

      private

      def superadmin_conflict?
        (@role == :admin && @user.superadmin?) || (@role == :superadmin && @user.superadmin?)
      end

      def admin_conflict?
        @role == :admin && @user.admin?
      end

      def action_name
        case @role
        when :admin then "user.grant_admin"
        when :superadmin then "user.grant_superadmin"
        when :user then @user.superadmin? ? "user.revoke_superadmin" : "user.revoke_admin"
        else "user.update"
        end
      end
    end
  end
end
