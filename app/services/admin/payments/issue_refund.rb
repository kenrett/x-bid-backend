module Admin
  module Payments
    class IssueRefund < Admin::BaseCommand
      def initialize(actor:, payment:, amount_cents: nil, reason: nil, request: nil, gateway: ::Payments::Gateway)
        super(actor: actor, payment: payment, amount_cents: amount_cents&.to_i, reason: reason, request: request, gateway: gateway, override_spent_credits: false)
      end

      private

      def perform
        return ServiceResult.fail("Payment not provided", code: :invalid_payment) unless @payment

        @payment.with_lock do
          return already_refunded if fully_refunded?
          if refund_already_recorded?
            return refund_exceeds_remaining if refund_request_exceeds_remaining?
            return already_refunded
          end
          return invalid_state("Payment is not refundable in its current state") unless refundable_state?

          amount = resolve_amount
          return invalid_amount("Refund amount must be positive") if amount <= 0
          return invalid_amount("Refund exceeds remaining balance", code: :amount_exceeds_charge) if amount > @payment.refundable_cents

          credits_to_revoke = credits_to_revoke_for(amount_cents: amount)
          balance_before_refund = Credits::Balance.for_user(@payment.user)
          if credits_to_revoke.positive? && !override_spent_credits? && Credits::Balance.for_user(@payment.user) < credits_to_revoke
            log_outcome(success: false, amount_cents: amount, errors: [ "Cannot refund: user has spent credits from this purchase" ], credits_to_revoke: credits_to_revoke)
            return ServiceResult.fail("Cannot refund: user has spent credits from this purchase", code: :cannot_refund_spent_credits, record: @payment)
          end

          response = @gateway.issue_refund(payment: @payment, amount_cents: amount, reason: @reason)
          unless response.success?
            log_outcome(success: false, amount_cents: amount, gateway_response: response)
            return ServiceResult.fail(response.error_message || "Unable to issue refund", code: :gateway_error, data: { gateway_code: response.error_code }, record: @payment)
          end

          refund_total_cents = @payment.refunded_cents.to_i + amount
          result = ::Payments::ApplyPurchaseRefund.call!(
            purchase: @payment,
            refunded_total_cents: refund_total_cents,
            refund_id: response.refund_id,
            reason: @reason,
            source: "admin_issue_refund"
          )
          unless result.ok?
            log_outcome(success: false, amount_cents: amount, gateway_response: response, errors: [ result.message ], credits_to_revoke: credits_to_revoke)
            return result
          end

          AuditLogger.log(action: "payment.refund", actor: @actor, target: @payment, payload: audit_payload(amount, response.refund_id), request: @request)
          if credits_to_revoke.positive? && balance_before_refund >= credits_to_revoke
            AuditLogger.log(
              action: "payment.refund_credit_reconcile",
              actor: @actor,
              target: @payment,
              payload: { refund_id: response.refund_id, credits_debited: credits_to_revoke, refunded_amount_cents: amount, policy: "proportional_safe" },
              request: @request
            )
          end

          log_outcome(success: true, amount_cents: amount, gateway_response: response, credits_to_revoke: credits_to_revoke)

          ServiceResult.ok(
            code: refund_code,
            message: "Refund issued",
            record: @payment,
            data: { payment: @payment, refund_id: response.refund_id, refund_amount_cents: amount, credits_reconciled: credits_to_revoke }
          )
        end
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to issue refund", code: :database_error, record: @payment)
      rescue => e
        log_exception(e)
        ServiceResult.fail("Unexpected error issuing refund", code: :unexpected_error, record: @payment)
      end

      def resolve_amount
        return @amount_cents if @amount_cents.present?

        @payment.refundable_cents
      end

      # Policy (hybrid-safe):
      # - Credits reversed are proportional to the refund amount.
      # - If the user has already spent credits (insufficient current balance), block unless override.
      def credits_to_revoke_for(amount_cents:)
        ::Payments::RefundPolicy.credits_to_revoke(purchase: @payment, refund_amount_cents: amount_cents)
      end

      def fully_refunded?
        @payment.refundable_cents <= 0 || @payment.refunded?
      end

      def refundable_state?
        !@payment.voided? && !@payment.failed? && %w[completed partially_refunded].include?(@payment.status)
      end

      def refund_already_recorded?
        return true if @payment.refunded_cents.to_i.positive? || @payment.refund_id.present? || @payment.refunded_at.present?
        return false if @payment.stripe_payment_intent_id.blank?

        MoneyEvent.exists?(event_type: :refund, source_type: "StripePaymentIntent", source_id: @payment.stripe_payment_intent_id.to_s)
      end

      def override_spent_credits?
        !!@override_spent_credits
      end

      def invalid_state(message)
        log_outcome(success: false, amount_cents: resolve_amount, errors: [ message ])
        ServiceResult.fail(message, code: :invalid_state, record: @payment)
      end

      def already_refunded
        log_outcome(success: true, amount_cents: 0, errors: [ "Payment already refunded" ])
        ServiceResult.ok(
          code: :already_refunded,
          message: "Payment already refunded",
          record: @payment,
          data: {
            idempotent: true,
            refund_id: @payment.refund_id,
            refund_amount_cents: 0,
            credits_reconciled: 0
          }.compact
        )
      end

      def refund_request_exceeds_remaining?
        return false if @amount_cents.blank?

        @amount_cents.to_i > @payment.refundable_cents.to_i
      end

      def refund_exceeds_remaining
        invalid_amount("Refund exceeds remaining balance", code: :amount_exceeds_charge)
      end

      def invalid_amount(message, code: :invalid_amount)
        log_outcome(success: false, amount_cents: @amount_cents, errors: [ message ])
        ServiceResult.fail(message, code: code, record: @payment)
      end

      def refund_code
        @payment.status == "refunded" ? :refunded : :partially_refunded
      end

      def audit_payload(amount_cents, refund_id)
        {
          amount_cents: amount_cents,
          reason: @reason,
          refund_id: refund_id
        }.compact
      end

      def log_outcome(success:, amount_cents:, gateway_response: nil, errors: nil, credits_to_revoke: nil)
        AppLogger.log(
          **base_log_context.merge(
            success: success,
            amount_cents: amount_cents,
            credits_to_revoke: credits_to_revoke,
            payment_status: @payment.status,
            refund_id: gateway_response&.refund_id || @payment.refund_id,
            gateway_code: gateway_response&.error_code,
            gateway_message: gateway_response&.error_message,
            errors: errors&.presence,
            gateway_response: gateway_response&.raw_response
          )
        )
      end

      def log_exception(error)
        AppLogger.error(event: "admin.payments.issue_refund.error", error: error, **base_log_context)
      end

      def base_log_context
        {
          event: "admin.payments.issue_refund",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          payment_id: @payment&.id,
          user_id: @payment&.user_id,
          payment_status: @payment&.status,
          reason: @reason
        }
      end
    end
  end
end
