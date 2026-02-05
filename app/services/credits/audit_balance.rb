module Credits
  class AuditBalance
    class << self
      def call(user:)
        raise ArgumentError, "User must be provided" unless user

        cached = user.bid_credits.to_i
        derived = Credits::Balance.derived_for_user(user)
        { cached: cached, derived: derived, matches: cached == derived }
      end
    end
  end
end
