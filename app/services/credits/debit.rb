require "securerandom"

module Credits
  class Debit
    class << self
      # Debits a user's bid credits for placing a bid, tied to an auction.
      # Raises if the user lacks credits or if the debit fails.
      # If `locked: false`, the call will acquire locks using the global user->auction order.
      def for_bid!(user:, auction:, idempotency_key:, locked: false)
        raise ArgumentError, "Auction must be provided" unless auction
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Idempotency key must be provided" if idempotency_key.blank?

        if locked
          debit!(user:, auction:, idempotency_key:)
        else
          LockOrder.with_user_then_auction(user:, auction:) { debit!(user:, auction:, idempotency_key:) }
        end
      end

      private

      def debit!(user:, auction:, idempotency_key:)
        existing = CreditTransaction.find_by(idempotency_key: idempotency_key)
        if existing
          raise ArgumentError, "Idempotency key belongs to a different user" if existing.user_id != user.id
          remaining = Credits::RebuildBalance.call!(user: user, lock: false)
          return log_debit(user:, auction:, remaining:)
        end

        Credits::Ledger.bootstrap!(user)

        balance = Credits::Balance.for_user(user)
        raise InsufficientCreditsError, "Insufficient bid credits" if balance <= 0

        begin
          CreditTransaction.create!(
            user: user,
            auction: auction,
            kind: :debit,
            amount: -1,
            reason: "bid_placed",
            idempotency_key: idempotency_key,
            metadata: {}
          )
        rescue ActiveRecord::RecordNotUnique
          existing = CreditTransaction.find_by!(idempotency_key: idempotency_key)
          raise ArgumentError, "Idempotency key belongs to a different user" if existing.user_id != user.id
        end

        remaining = Credits::RebuildBalance.call!(user: user, lock: false)
        log_debit(user:, auction:, remaining:)
      end

      def log_debit(user:, auction:, remaining:)
        AppLogger.log(event: "credits.debit", user_id: user.id, auction_id: auction.id, remaining: remaining)
      end
    end

    class InsufficientCreditsError < StandardError; end
  end
end
