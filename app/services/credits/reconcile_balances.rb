module Credits
  class ReconcileBalances
    class << self
      def call!(fix: false, limit: nil, scope: User.all)
        stats = { checked: 0, drifted: 0, fixed: 0 }

        relation = scope.order(:id)
        relation = relation.limit(limit) if limit

        relation.find_each do |user|
          stats[:checked] += 1
          Credits::Ledger.bootstrap!(user)
          cached = user.bid_credits.to_i
          derived = Credits::Balance.derived_for_user(user)
          next if cached == derived

          stats[:drifted] += 1
          AppLogger.log(
            event: "credits.balance.drift",
            user_id: user.id,
            cached: cached,
            derived: derived,
            fix: fix
          )

          next unless fix

          user.with_lock do
            Credits::MaterializedBalance.set!(user, derived)
          end
          stats[:fixed] += 1
          AppLogger.log(
            event: "credits.balance.reconciled",
            user_id: user.id,
            cached: cached,
            derived: derived
          )
        end

        stats
      end
    end
  end
end
