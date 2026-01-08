require "securerandom"

module Credits
  module Ledger
    module_function

    # Seeds the ledger with the user's current cached balance if no entries exist.
    # Allows legacy users with cached bid_credits to transition to ledger-derived balances.
    def bootstrap!(user)
      raise ArgumentError, "User must be provided" unless user
      return if CreditTransaction.exists?(user_id: user.id)

      cached = user.bid_credits.to_i
      return if cached.zero?

      CreditTransaction.create!(
        user: user,
        kind: :grant,
        amount: cached,
        reason: "opening balance snapshot",
        idempotency_key: "bootstrap:user:#{user.id}",
        metadata: { bootstrap: true },
        storefront_key: Current.storefront_key.to_s.presence
      )
    rescue ActiveRecord::RecordNotUnique
      # If two threads race to bootstrap, the unique idempotency_key prevents duplicates.
      nil
    end
  end
end
