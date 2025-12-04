module Admin
  module Users
    class BanUser
      def initialize(actor:, user:, request: nil)
        @actor = actor
        @user = user
        @request = request
      end

      def call
        return ServiceResult.fail("User already disabled") if @user.disabled?

        @user.disable_and_revoke_sessions!
        AuditLogger.log(action: "user.ban", actor: @actor, target: @user, request: @request)
        ServiceResult.ok(user: @user)
      rescue ActiveRecord::ActiveRecordError => e
        ServiceResult.fail("Unable to disable user: #{e.message}")
      end
    end
  end
end
