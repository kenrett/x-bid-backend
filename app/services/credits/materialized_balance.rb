module Credits
  class MaterializedBalance
    class << self
      def apply_delta!(user, delta)
        raise ArgumentError, "User must be provided" unless user

        user.update!(bid_credits: user.bid_credits.to_i + delta.to_i)
        user.bid_credits.to_i
      end

      def set!(user, value)
        raise ArgumentError, "User must be provided" unless user

        user.update!(bid_credits: value.to_i)
        user.bid_credits.to_i
      end
    end
  end
end
