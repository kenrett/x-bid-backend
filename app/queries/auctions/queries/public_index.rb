module Auctions
  module Queries
    class PublicIndex
      def initialize(relation: Auction.all)
        @relation = relation
      end

      def call
        ServiceResult.ok(records: scoped_relation)
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
