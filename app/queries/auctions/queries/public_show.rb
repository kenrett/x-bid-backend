module Auctions
  module Queries
    class PublicShow
      def initialize(id:, relation: Auction.all)
        @id = id
        @relation = relation
      end

      def call
        auction = scoped_relation.includes(:bids, :winning_user).find_by(id: id)
        return ServiceResult.fail("Auction not found", code: :not_found) unless auction

        ServiceResult.ok(record: auction)
      end

      private

      attr_reader :id, :relation

      def scoped_relation
        relation.select(
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
      end
    end
  end
end
