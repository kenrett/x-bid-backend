module Admin
  module Users
    class GrantRole
      def initialize(actor:, user:, role:, request: nil, allow_superadmin_demotion: false)
        @actor = actor
        @user = user
        @role = role.to_sym
        @request = request
        @allow_superadmin_demotion = !!allow_superadmin_demotion
      end

      def call
        return ServiceResult.fail("User is already a superadmin") if superadmin_conflict?
        return ServiceResult.fail("User is already an admin") if admin_conflict?

        previous_role = @user.role
        if @user.update(role: @role)
          sessions_revoked = revoke_sessions_after_role_change(previous_role)
          AuditLogger.log(action: action_name, actor: @actor, target: @user, request: @request)
          ServiceResult.ok(user: @user, data: { sessions_revoked: sessions_revoked })
        else
          ServiceResult.fail(@user.errors.full_messages.to_sentence)
        end
      end

      private

      def superadmin_conflict?
        return true if @role == :superadmin && @user.superadmin?
        return false unless @role == :admin && @user.superadmin?

        !@allow_superadmin_demotion
      end

      def admin_conflict?
        @role == :admin && @user.admin?
      end

      def action_name
        case @role
        when :admin then @user.superadmin? ? "user.revoke_superadmin" : "user.grant_admin"
        when :superadmin then "user.grant_superadmin"
        when :user then @user.superadmin? ? "user.revoke_superadmin" : "user.revoke_admin"
        else "user.update"
        end
      end

      def revoke_sessions_after_role_change(previous_role)
        return 0 if previous_role.to_s == @user.role.to_s

        Auth::RevokeUserSessions.new(
          user: @user,
          reason: "role_change",
          actor: @actor,
          actor_session_token_id: Current.session_token_id,
          request: @request
        ).call
      end
    end
  end
end
