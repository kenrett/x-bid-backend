require "securerandom"

module Credits
  class Apply
    class << self
      # Credits bid credits to a user for any reason (e.g., purchase, refund).
      # Uses the ledger as the source of truth and keeps the cached balance in sync.
      def apply!(user:, reason:, amount:, idempotency_key:, kind: :grant, purchase: nil, auction: nil, admin_actor: nil, stripe_event: nil, stripe_payment_intent_id: nil, stripe_checkout_session_id: nil, metadata: {})
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Reason must be provided" if reason.blank?
        raise ArgumentError, "Amount must be non-zero" if amount.to_i == 0

        normalized_kind = kind.to_s
        normalized_amount = amount.to_i
        if normalized_kind == "grant" || normalized_kind == "refund"
          raise ArgumentError, "#{normalized_kind} amount must be positive" unless normalized_amount.positive?
        end
        if normalized_kind == "debit"
          raise ArgumentError, "debit amount must be negative" unless normalized_amount.negative?
        end
        if reason.to_s == "bid_pack_purchase" && purchase.nil?
          AppLogger.log(
            event: "credits.grant_without_purchase",
            level: :error,
            user_id: user.id,
            idempotency_key: idempotency_key,
            reason: reason,
            kind: kind,
            stripe_payment_intent_id: stripe_payment_intent_id,
            stripe_checkout_session_id: stripe_checkout_session_id,
            stripe_event_id: stripe_event&.stripe_event_id
          )
          raise ArgumentError, "Credits for bid_pack_purchase require a purchase"
        end

        user.with_lock do
          existing = CreditTransaction.find_by(idempotency_key: idempotency_key)
          if existing
            raise ArgumentError, "Idempotency key belongs to a different user" if existing.user_id != user.id
            return Credits::RebuildBalance.call!(user: user, lock: false)
          end

          Credits::Ledger.bootstrap!(user)

          begin
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
          rescue ActiveRecord::RecordNotUnique
            existing = CreditTransaction.find_by!(idempotency_key: idempotency_key)
            raise ArgumentError, "Idempotency key belongs to a different user" if existing.user_id != user.id
          end

          new_balance = Credits::RebuildBalance.call!(user: user, lock: false)
          AppLogger.log(
            event: "credits.credit",
            user_id: user.id,
            reason: reason,
            amount: amount,
            balance: new_balance,
            purchase_id: purchase&.id,
            auction_id: auction&.id,
            stripe_payment_intent_id: stripe_payment_intent_id,
            stripe_checkout_session_id: stripe_checkout_session_id,
            stripe_event_id: stripe_event&.stripe_event_id
          )
          new_balance
        end
      end
    end
  end
end
