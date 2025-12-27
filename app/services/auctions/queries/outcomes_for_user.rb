module Auctions
  module Queries
    class OutcomesForUser
      Outcome = Struct.new(:type, :auction, :created_at, keyword_init: true)

      attr_reader :records

      def self.call(user:, relation: Auction.all)
        new(user: user, relation: relation).call
      end

      def initialize(user:, relation: Auction.all)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @relation = relation
        @records = []
      end

      def call
        ended = relation.where(status: :ended)
        won = ended.where(winning_user_id: user.id)
        lost = ended
          .joins(:bids)
          .where(bids: { user_id: user.id })
          .where.not(winning_user_id: user.id)
          .distinct

        won.find_each { |auction| @records << Outcome.new(type: "auction_won", auction: auction, created_at: outcome_created_at_for(auction)) }
        lost.find_each { |auction| @records << Outcome.new(type: "auction_lost", auction: auction, created_at: outcome_created_at_for(auction)) }

        @records.sort_by! { |outcome| [ outcome.created_at.to_i, outcome.auction.id ] }.reverse!
        self
      end

      private

      attr_reader :user, :relation

      def outcome_created_at_for(auction)
        auction.end_time || auction.updated_at || auction.created_at
      end
    end
  end
end
