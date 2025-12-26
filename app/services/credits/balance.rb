module Credits
  module Balance
    module_function

    def for_user(user)
      raise ArgumentError, "User must be provided" unless user

      scope = CreditTransaction.where(user: user)
      sum = scope.sum(:amount).to_i
      return sum if sum != 0 || scope.exists?

      # Fallback for legacy data while the ledger backfills; treats cached
      # bid_credits as the starting point when no ledger entries exist.
      user.bid_credits.to_i
    end
  end
end
