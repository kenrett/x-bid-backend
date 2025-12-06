module Credits
  class Apply
    class << self
      # Credits bid credits to a user for any reason (e.g., purchase, refund).
      def apply!(user:, reason:, amount:)
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Amount must be positive" unless amount.to_i > 0

        user.with_lock do
          user.increment!(:bid_credits, amount)
          AppLogger.log(event: "credits.credit", user_id: user.id, reason: reason, amount: amount, balance: user.bid_credits)
        end
      end
    end
  end
end
