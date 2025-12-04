module Credits
  class Credit
    class << self
      # Credits a user's bid credits (e.g., refunds or adjustments).
      def for_refund!(user:, reason:, amount: 0)
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Amount must be positive" unless amount.to_i > 0

        user.with_lock do
          user.increment!(:bid_credits, amount)
          log_credit(user:, reason:, amount:)
        end
      end

      private

      def log_credit(user:, reason:, amount:)
        Rails.logger.info("Credits::Credit refund | user_id=#{user.id} reason=#{reason} amount=#{amount} balance=#{user.bid_credits}")
      end
    end
  end
end
