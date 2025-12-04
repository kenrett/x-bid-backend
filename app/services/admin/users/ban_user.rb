module Admin
  module Users
    class BanUser
      Result = Struct.new(:user, :error, keyword_init: true)

      def initialize(actor:, user:, request: nil)
        @actor = actor
        @user = user
        @request = request
      end

      def call
        return Result.new(error: "User already disabled") if @user.disabled?

        @user.disable_and_revoke_sessions!
        AuditLogger.log(action: "user.ban", actor: @actor, target: @user, request: @request)
        Result.new(user: @user)
      rescue ActiveRecord::ActiveRecordError => e
        Result.new(error: "Unable to disable user: #{e.message}")
      end
    end
  end
end
