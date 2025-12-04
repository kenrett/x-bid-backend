module Credits
  class Debit
    class << self
      # Debits a user's bid credits for placing a bid, tied to an auction.
      # Raises if the user lacks credits or if the debit fails.
      def for_bid!(user:, auction:)
        raise ArgumentError, "Auction must be provided" unless auction
        raise ArgumentError, "User must be provided" unless user

        raise InsufficientCreditsError, "Insufficient bid credits" if user.bid_credits.to_i <= 0

        user.with_lock do
          raise InsufficientCreditsError, "Insufficient bid credits" if user.bid_credits.to_i <= 0
          user.decrement!(:bid_credits)
          log_debit(user:, auction:)
        end
      end

      private

      def log_debit(user:, auction:)
        Rails.logger.info("Credits::Debit bid | user_id=#{user.id} auction_id=#{auction.id} remaining=#{user.bid_credits}")
      end
    end

    class InsufficientCreditsError < StandardError; end
  end
end
