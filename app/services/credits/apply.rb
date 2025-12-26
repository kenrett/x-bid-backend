require "securerandom"

module Credits
  class Apply
    class << self
      # Credits bid credits to a user for any reason (e.g., purchase, refund).
      # Uses the ledger as the source of truth and keeps the cached balance in sync.
      def apply!(user:, reason:, amount:, kind: :grant, idempotency_key: nil, purchase: nil, auction: nil, admin_actor: nil, stripe_event: nil, stripe_payment_intent_id: nil, stripe_checkout_session_id: nil, metadata: {})
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Reason must be provided" if reason.blank?
        raise ArgumentError, "Amount must be positive" unless amount.to_i > 0

        idempotency_key ||= SecureRandom.uuid

        user.with_lock do
          Credits::Ledger.bootstrap!(user)

          CreditTransaction.create!(
            user: user,
            kind: kind,
            amount: amount.to_i,
            reason: reason,
            idempotency_key: idempotency_key,
            purchase: purchase,
            auction: auction,
            admin_actor: admin_actor,
            stripe_event: stripe_event,
            stripe_payment_intent_id: stripe_payment_intent_id,
            stripe_checkout_session_id: stripe_checkout_session_id,
            metadata: metadata || {}
          )

          new_balance = Credits::RebuildBalance.call!(user: user, lock: false)
          AppLogger.log(event: "credits.credit", user_id: user.id, reason: reason, amount: amount, balance: new_balance, purchase_id: purchase&.id, auction_id: auction&.id)
        end
      end
    end
  end
end
