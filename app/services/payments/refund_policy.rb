module Payments
  class RefundPolicy
    class << self
      def credits_to_revoke(purchase:, refund_amount_cents:)
        total_cents = purchase.amount_cents.to_i
        credits_granted = credits_granted_for(purchase)
        refund_cents = refund_amount_cents.to_i
        return 0 if total_cents <= 0 || credits_granted <= 0 || refund_cents <= 0

        proportional = (credits_granted * refund_cents.to_r / total_cents).round
        proportional.clamp(0, credits_granted)
      end

      def credit_reconcile_idempotency_key(purchase:)
        payment_intent_id = purchase.stripe_payment_intent_id.to_s
        raise ArgumentError, "stripe_payment_intent_id required for refund idempotency" if payment_intent_id.blank?

        "purchase:#{purchase.id}:refund:#{payment_intent_id}:credits_reconcile"
      end

      private

      def credits_granted_for(purchase)
        pack_credits = purchase.bid_pack&.bids.to_i
        return 0 if pack_credits <= 0

        grant_key = "purchase:#{purchase.id}:grant"
        return 0 unless CreditTransaction.exists?(idempotency_key: grant_key)

        pack_credits
      end
    end
  end
end
