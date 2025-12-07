module Auctions
  module Queries
    class AdminShow < Base
      attr_reader :record

      def initialize(params: {}, relation: Auction.all)
        super(params: params)
        @relation = relation
      end

      def call
        @record = admin_scope.includes(:bids, :winning_user).find(params[:id])
        self
      end

      private

      attr_reader :relation

      def admin_scope
        relation
      end
    end
  end
end
