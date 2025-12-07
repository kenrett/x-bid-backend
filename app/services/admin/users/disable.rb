module Admin
  module Users
    class Disable < Admin::BaseCommand
      def initialize(actor:, user:, reason: nil, request: nil)
        super(actor: actor, user: user, reason: reason, request: request)
      end

      private

      def perform
        return already_disabled if @user.disabled?

        @user.disable_and_revoke_sessions!
        AuditLogger.log(action: "user.disable", actor: @actor, target: @user, payload: { reason: @reason }.compact, request: @request)
        log_outcome(success: true, from_status: "active", to_status: @user.status)
        ServiceResult.ok(code: :disabled, message: "User disabled", record: @user, data: { user: @user })
      rescue ActiveRecord::RecordInvalid => e
        log_outcome(success: false, errors: e.record.errors.full_messages, from_status: @user.status)
        ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :invalid_user, record: e.record)
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to disable user", code: :invalid_user, record: @user)
      end

      def already_disabled
        log_outcome(success: true, from_status: @user.status, to_status: @user.status, note: "already_disabled")
        ServiceResult.ok(code: :already_disabled, message: "User already disabled", record: @user, data: { user: @user })
      end

      def base_log_context
        {
          event: "admin.users.disable",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          user_id: @user&.id,
          user_email: @user&.email_address,
          reason: @reason
        }
      end

      def log_outcome(success:, from_status: nil, to_status: nil, errors: nil, note: nil)
        AppLogger.log(**base_log_context.merge(success: success, from_status: from_status, to_status: to_status, errors: errors&.presence, note: note))
      end

      def log_exception(error)
        AppLogger.error(event: "admin.users.disable.error", error: error, **base_log_context)
      end
    end
  end
end
