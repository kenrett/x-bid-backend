module Auctions
  module Queries
    class PublicIndex < Base
      def self.call(params: {}, relation: Auction.all)
        new(params: params, relation: relation).call
      end

      def initialize(params: {}, relation: Auction.all)
        super(params: params)
        @relation = relation
      end

      def call
        @records = scoped_relation
        self
      end

      private

      attr_reader :relation

      def scoped_relation
        relation
          .select(
            :id,
            :title,
            :description,
            :start_date,
            :end_time,
            :current_price,
            :image_url,
            :status,
            :winning_user_id
          )
          .includes(:winning_user)
      end
    end
  end
end
