module Credits
  class RebuildBalance
    class << self
      def call!(user:, lock: true)
        raise ArgumentError, "User must be provided" unless user

        return update_balance(user) unless lock

        user.with_lock { update_balance(user) }
      end

      private

      def update_balance(user)
        balance = Credits::Balance.for_user(user)
        user.update!(bid_credits: balance)
        balance
      end
    end
  end
end
