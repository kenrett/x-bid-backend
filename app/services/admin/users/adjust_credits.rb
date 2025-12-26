require "securerandom"

module Admin
  module Users
    class AdjustCredits < Admin::BaseCommand
      def initialize(actor:, user:, delta:, reason: nil, request: nil)
        super(actor: actor, user: user, delta: delta.to_i, reason: reason, request: request)
      end

      private

      def perform
        return ServiceResult.fail("Delta must be non-zero", code: :invalid_delta) if @delta.zero?

        @user.with_lock do
          derived_balance = Credits::Balance.for_user(@user)
          new_balance = derived_balance + @delta
          return insufficient_balance(derived_balance) if new_balance.negative?

          Credits::Apply.apply!(
            user: @user,
            reason: @reason.presence || "admin adjustment",
            amount: @delta,
            kind: :adjustment,
            idempotency_key: "admin_adjustment:#{@actor.id}:#{@user.id}:#{SecureRandom.uuid}",
            admin_actor: @actor,
            metadata: { request_path: @request&.path, delta: @delta, source: "admin_adjust_credits" }.compact
          )

          updated_balance = Credits::RebuildBalance.call!(user: @user, lock: false)
          AuditLogger.log(action: "user.adjust_credits", actor: @actor, target: @user, payload: { delta: @delta, reason: @reason }, request: @request)
          log_outcome(success: true, old_balance: derived_balance, new_balance: updated_balance)
          ServiceResult.ok(code: :ok, message: "Credits adjusted", record: @user, data: { user: @user })
        end
      rescue ActiveRecord::RecordInvalid => e
        log_outcome(success: false, errors: @user.errors.full_messages)
        ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :invalid_user, record: e.record)
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to adjust credits", code: :invalid_user, record: @user)
      end

      def insufficient_balance(old_balance)
        log_outcome(success: false, old_balance: old_balance, new_balance: old_balance + @delta, errors: [ "Insufficient credits" ])
        ServiceResult.fail("Insufficient credits", code: :insufficient_credits, record: @user)
      end

      def base_log_context
        {
          event: "admin.users.adjust_credits",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          user_id: @user&.id,
          user_email: @user&.email_address,
          delta: @delta,
          reason: @reason
        }
      end

      def log_outcome(success:, old_balance: nil, new_balance: nil, errors: nil)
        AppLogger.log(**base_log_context.merge(success: success, old_balance: old_balance, new_balance: new_balance, errors: errors&.presence))
      end

      def log_exception(error)
        AppLogger.error(event: "admin.users.adjust_credits.error", error: error, **base_log_context)
      end
    end
  end
end
