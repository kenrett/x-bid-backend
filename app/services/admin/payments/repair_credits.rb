module Admin
  module Payments
    class RepairCredits < Admin::BaseCommand
      def initialize(actor:, purchase:, request: nil)
        super(actor: actor, purchase: purchase, request: request)
      end

      private

      def perform
        return ServiceResult.fail("Payment not provided", code: :invalid_payment) unless @purchase

        @purchase.with_lock do
          result = ::Payments::ApplyBidPackPurchase.call!(
            user: @purchase.user,
            bid_pack: @purchase.bid_pack,
            stripe_checkout_session_id: @purchase.stripe_checkout_session_id,
            stripe_payment_intent_id: @purchase.stripe_payment_intent_id,
            stripe_event_id: @purchase.stripe_event_id,
            amount_cents: @purchase.amount_cents,
            currency: @purchase.currency,
            source: "admin_repair_credits"
          )

          AuditLogger.log(
            action: "payment.repair_credits",
            actor: @actor,
            target: @purchase,
            payload: audit_payload(result),
            request: @request
          )

          AppLogger.log(**base_log_context.merge(success: result.ok?, idempotent: result.idempotent, code: result.code))

          result
        end
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to repair credits", code: :database_error, record: @purchase)
      rescue => e
        log_exception(e)
        ServiceResult.fail("Unexpected error repairing credits", code: :unexpected_error, record: @purchase)
      end

      def audit_payload(result)
        {
          idempotent: result.idempotent,
          code: result.code,
          credit_transaction_id: result.credit_transaction&.id,
          credit_idempotency_key: result.credit_transaction&.idempotency_key
        }.compact
      end

      def log_exception(error)
        AppLogger.error(event: "admin.payments.repair_credits.error", error: error, **base_log_context)
      end

      def base_log_context
        {
          event: "admin.payments.repair_credits",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          payment_id: @purchase&.id,
          user_id: @purchase&.user_id,
          stripe_payment_intent_id: @purchase&.stripe_payment_intent_id,
          stripe_checkout_session_id: @purchase&.stripe_checkout_session_id,
          stripe_event_id: @purchase&.stripe_event_id
        }
      end
    end
  end
end
