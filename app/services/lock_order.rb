module LockOrder
  module_function

  # Global lock order for operations that need both user and auction rows.
  # Always acquire the user lock before the auction lock to avoid deadlocks.
  def with_user_then_auction(user:, auction:, **transaction_options, &block)
    raise ArgumentError, "Block required" unless block
    ActiveRecord::Base.transaction(**transaction_options) do
      lock_user_then_auction!(user: user, auction: auction)
      yield
    end
  end

  def lock_user_then_auction!(user:, auction:)
    raise ArgumentError, "User must be provided" unless user
    raise ArgumentError, "Auction must be provided" unless auction

    user.lock!
    auction.lock!
  end
end
