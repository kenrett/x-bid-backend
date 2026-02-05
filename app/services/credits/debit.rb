require "securerandom"

module Credits
  class Debit
    class << self
      # Debits a user's bid credits for placing a bid, tied to an auction.
      # Raises if the user lacks credits or if the debit fails.
      # If `locked: false`, the call will acquire locks using the global user->auction order.
      def for_bid!(user:, auction:, idempotency_key:, locked: false, storefront_key: nil)
        raise ArgumentError, "Auction must be provided" unless auction
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Idempotency key must be provided" if idempotency_key.blank?

        if locked
          debit!(user:, auction:, idempotency_key:, storefront_key:)
        else
          LockOrder.with_user_then_auction(user:, auction:) { debit!(user:, auction:, idempotency_key:, storefront_key:) }
        end
      end

      private

      def debit!(user:, auction:, idempotency_key:, storefront_key:)
        existing = CreditTransaction.find_by(idempotency_key: idempotency_key)
        if existing
          raise ArgumentError, "Idempotency key belongs to a different user" if existing.user_id != user.id
          return log_debit(user:, auction:, remaining: user.bid_credits.to_i)
        end

        Credits::Ledger.bootstrap!(user)

        balance = Credits::Balance.for_user(user)
        raise InsufficientCreditsError, "Insufficient bid credits" if balance <= 0

        resolved_storefront_key =
          storefront_key.to_s.presence || Current.storefront_key.to_s.presence || auction.storefront_key.to_s.presence

        Credits::Ledger::Writer.write!(
          user: user,
          auction: auction,
          kind: :debit,
          amount: -1,
          reason: "bid_placed",
          idempotency_key: idempotency_key,
          storefront_key: resolved_storefront_key,
          metadata: {},
          entry_type: "bid_spend"
        )

        remaining = Credits::MaterializedBalance.apply_delta!(user, -1)
        log_debit(user:, auction:, remaining:)
      end

      def log_debit(user:, auction:, remaining:)
        AppLogger.log(event: "credits.debit", user_id: user.id, auction_id: auction.id, remaining: remaining)
      end
    end

    class InsufficientCreditsError < StandardError; end
  end
end
