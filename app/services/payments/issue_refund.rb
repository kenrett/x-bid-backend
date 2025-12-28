module Payments
  class IssueRefund
    def initialize(purchase:, amount_cents:, reason: nil, gateway: Payments::Gateway)
      @purchase = purchase
      @amount_cents = amount_cents.to_i
      @reason = reason
      @gateway = gateway
    end

    def call
      return ServiceResult.fail("Purchase not provided", code: :invalid_payment) unless @purchase

      @purchase.with_lock do
        return ServiceResult.fail("Payment intent missing", code: :missing_payment_intent) if payment_intent_id.blank?
        return ServiceResult.fail("Refund amount must be positive", code: :invalid_amount) if @amount_cents <= 0
        return ServiceResult.fail("Refund exceeds original purchase amount", code: :amount_exceeds_charge) if @amount_cents > @purchase.amount_cents.to_i
        return ServiceResult.fail("Refund already recorded", code: :already_refunded) if refund_already_recorded?

        response = @gateway.issue_refund(payment: @purchase, amount_cents: @amount_cents, reason: @reason)
        unless response.success?
          AppLogger.log(
            event: "payments.issue_refund.gateway_error",
            level: :error,
            purchase_id: @purchase.id,
            user_id: @purchase.user_id,
            payment_intent_id: payment_intent_id,
            error_code: response.error_code,
            error_message: response.error_message
          )
          return ServiceResult.fail(response.error_message || "Unable to issue refund", code: :gateway_error, record: @purchase)
        end

        money_event = MoneyEvent.create!(
          user: @purchase.user,
          event_type: :refund,
          amount_cents: -@amount_cents,
          currency: @purchase.currency,
          source_type: "StripePaymentIntent",
          source_id: payment_intent_id,
          occurred_at: Time.current,
          metadata: {
            purchase_id: @purchase.id,
            refund_id: response.refund_id,
            reason: @reason
          }.compact
        )

        AppLogger.log(
          event: "payments.issue_refund.recorded",
          purchase_id: @purchase.id,
          user_id: @purchase.user_id,
          payment_intent_id: payment_intent_id,
          refund_id: response.refund_id,
          amount_cents: @amount_cents,
          money_event_id: money_event.id
        )

        ServiceResult.ok(
          code: :refunded,
          message: "Refund recorded",
          data: { purchase: @purchase, refund_id: response.refund_id, money_event: money_event }
        )
      end
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.fail("Refund already recorded", code: :already_refunded, record: @purchase)
    rescue => e
      AppLogger.error(
        event: "payments.issue_refund.error",
        error: e,
        purchase_id: @purchase&.id,
        user_id: @purchase&.user_id,
        payment_intent_id: payment_intent_id
      )
      ServiceResult.fail("Unable to issue refund", code: :unexpected_error, record: @purchase)
    end

    private

    def payment_intent_id
      @purchase&.stripe_payment_intent_id.to_s
    end

    def refund_already_recorded?
      MoneyEvent.exists?(event_type: :refund, source_type: "StripePaymentIntent", source_id: payment_intent_id)
    end
  end
end
