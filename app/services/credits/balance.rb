module Credits
  module Balance
    module_function

    def for_user(user)
      raise ArgumentError, "User must be provided" unless user

      user.bid_credits.to_i
    end

    def derived_for_user(user)
      raise ArgumentError, "User must be provided" unless user

      scope = CreditTransaction.where(user: user)
      sum = scope.sum(:amount).to_i
      return sum if sum != 0 || scope.exists?

      # Fallback for legacy users with cached bid_credits and no ledger entries.
      user.bid_credits.to_i
    end
  end
end
