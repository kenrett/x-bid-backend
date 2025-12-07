module Admin
  module Payments
    class IssueRefund < Admin::BaseCommand
      def initialize(actor:, payment:, amount_cents: nil, reason: nil, request: nil, gateway: ::Payments::Gateway)
        super(actor: actor, payment: payment, amount_cents: amount_cents&.to_i, reason: reason, request: request, gateway: gateway)
      end

      private

      def perform
        return ServiceResult.fail("Payment not provided", code: :invalid_payment) unless @payment

        @payment.with_lock do
          return already_refunded if fully_refunded?
          return invalid_state("Payment is not refundable in its current state") unless refundable_state?

          amount = resolve_amount
          return invalid_amount("Refund amount must be positive") if amount <= 0
          return invalid_amount("Refund exceeds remaining balance", code: :amount_exceeds_charge) if amount > @payment.refundable_cents

          response = @gateway.issue_refund(payment: @payment, amount_cents: amount, reason: @reason)
          unless response.success?
            log_outcome(success: false, amount_cents: amount, gateway_response: response)
            return ServiceResult.fail(response.error_message || "Unable to issue refund", code: :gateway_error, data: { gateway_code: response.error_code }, record: @payment)
          end

          apply_refund(amount_cents: amount, refund_id: response.refund_id)
          log_outcome(success: true, amount_cents: amount, gateway_response: response)

          ServiceResult.ok(
            code: refund_code,
            message: "Refund issued",
            record: @payment,
            data: { payment: @payment, refund_id: response.refund_id, refund_amount_cents: amount }
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

      def apply_refund(amount_cents:, refund_id:)
        new_total_refunded = @payment.refunded_cents.to_i + amount_cents
        new_status = new_total_refunded >= @payment.amount_cents ? "refunded" : "partially_refunded"

        @payment.update!(
          refunded_cents: new_total_refunded,
          refund_id: refund_id,
          refund_reason: @reason.presence || @payment.refund_reason,
          refunded_at: Time.current,
          status: new_status
        )

        AuditLogger.log(action: "payment.refund", actor: @actor, target: @payment, payload: audit_payload(amount_cents, refund_id), request: @request)
      end

      def fully_refunded?
        @payment.refundable_cents <= 0 || @payment.refunded?
      end

      def refundable_state?
        !@payment.voided? && !@payment.failed? && %w[completed partially_refunded].include?(@payment.status)
      end

      def invalid_state(message)
        log_outcome(success: false, amount_cents: resolve_amount, errors: [ message ])
        ServiceResult.fail(message, code: :invalid_state, record: @payment)
      end

      def already_refunded
        log_outcome(success: false, amount_cents: 0, errors: [ "Payment already refunded" ])
        ServiceResult.fail("Payment already refunded", code: :already_refunded, record: @payment)
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

      def log_outcome(success:, amount_cents:, gateway_response: nil, errors: nil)
        AppLogger.log(
          **base_log_context.merge(
            success: success,
            amount_cents: amount_cents,
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
