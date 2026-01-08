module Payments
  class ApplyPurchaseRefund
    class << self
      def call!(purchase:, refunded_total_cents:, refund_id: nil, reason: nil, source:)
        raise ArgumentError, "Purchase must be provided" unless purchase
        raise ArgumentError, "Source must be provided" if source.blank?

        payment_intent_id = purchase.stripe_payment_intent_id.to_s
        return ServiceResult.fail("Missing payment intent", code: :missing_payment_intent, record: purchase) if payment_intent_id.blank?

        requested_total = refunded_total_cents.to_i
        return ServiceResult.ok(code: :ignored, message: "Refund amount is zero", data: { purchase_id: purchase.id }) if requested_total <= 0

        purchase.with_lock do
          total_cents = purchase.amount_cents.to_i
          refund_total = requested_total
          refund_total = total_cents if total_cents.positive? && refund_total > total_cents

          new_total_refunded = [ purchase.refunded_cents.to_i, refund_total ].max
          new_status = new_total_refunded >= total_cents ? "refunded" : "partially_refunded"

          credits_to_revoke = Payments::RefundPolicy.credits_to_revoke(purchase: purchase, refund_amount_cents: new_total_refunded)
          already_had_money_event = MoneyEvent.exists?(event_type: :refund, source_type: "StripePaymentIntent", source_id: payment_intent_id)
          credit_key = credits_to_revoke.positive? ? Payments::RefundPolicy.credit_reconcile_idempotency_key(purchase: purchase) : nil
          already_had_credit_tx = credit_key.present? ? CreditTransaction.exists?(idempotency_key: credit_key) : false

          ActiveRecord::Base.transaction do
            purchase.update!(
              refunded_cents: new_total_refunded,
              refund_id: purchase.refund_id.presence || refund_id.presence,
              refund_reason: purchase.refund_reason.presence || reason.presence,
              refunded_at: purchase.refunded_at.presence || Time.current,
              status: new_status
            )

            begin
              MoneyEvent.create!(
                user: purchase.user,
                event_type: :refund,
                amount_cents: -new_total_refunded,
                currency: purchase.currency,
                source_type: "StripePaymentIntent",
                source_id: payment_intent_id,
                occurred_at: Time.current,
                metadata: { purchase_id: purchase.id, refund_id: refund_id, reason: reason, source: source }.compact,
                storefront_key: purchase.storefront_key
              )
            rescue ActiveRecord::RecordNotUnique
              nil
            end

            if credits_to_revoke.positive?
              current_balance = Credits::Balance.for_user(purchase.user)
              if current_balance < credits_to_revoke
                AppLogger.log(
                  event: "payments.refund.spent_credits_blocked",
                  level: :error,
                  payment_intent_id: payment_intent_id,
                  purchase_id: purchase.id,
                  user_id: purchase.user_id,
                  credits_to_revoke: credits_to_revoke,
                  current_balance: current_balance,
                  source: source
                )
              else
                Credits::Apply.apply!(
                  user: purchase.user,
                  reason: "purchase_refund_credit_reversal",
                  amount: -credits_to_revoke,
                  idempotency_key: credit_key,
                  kind: :debit,
                  purchase: purchase,
                  storefront_key: purchase.storefront_key,
                  stripe_payment_intent_id: payment_intent_id,
                  stripe_checkout_session_id: purchase.stripe_checkout_session_id,
                  metadata: { source: source, refund_id: refund_id, refunded_amount_cents: new_total_refunded, policy: "proportional_safe" }.compact
                )
              end
            end
          end

          idempotent = already_had_money_event || already_had_credit_tx
          ServiceResult.ok(
            code: new_status.to_sym,
            message: "Refund applied",
            data: { purchase: purchase, refund_total_cents: new_total_refunded, credits_to_revoke: credits_to_revoke, idempotent: idempotent }
          )
        end
      rescue => e
        AppLogger.error(event: "payments.apply_refund.error", error: e, purchase_id: purchase&.id, payment_intent_id: purchase&.stripe_payment_intent_id, source: source)
        ServiceResult.fail("Unable to apply refund", code: :processing_error, record: purchase)
      end
    end
  end
end
