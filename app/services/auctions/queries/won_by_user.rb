module Auctions
  module Queries
    class WonByUser < Base
      def self.call(user:, params: {}, relation: AuctionSettlement.all)
        new(user: user, params: params, relation: relation).call
      end

      def initialize(user:, params: {}, relation: AuctionSettlement.all)
        raise ArgumentError, "User must be provided" unless user

        super(params: params)
        @user = user
        @relation = relation
      end

      def call
        @records = scoped_relation
        self
      end

      private

      attr_reader :user, :relation

      def scoped_relation
        relation
          .where(winning_user_id: user.id)
          .includes(:auction, :winning_bid, :auction_fulfillment)
          .order(ended_at: :desc, id: :desc)
      end
    end
  end
end
