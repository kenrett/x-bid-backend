module Auctions
  module Queries
    class PublicShow < Base
      attr_reader :record

      def self.call(params: {}, relation: Auction.all)
        new(params: params, relation: relation).call
      end

      def initialize(params: {}, relation: Auction.all)
        super(params: params)
        @relation = relation
      end

      def call
        @record = scoped_relation.includes(:bids, :winning_user).find_by!(id: params[:id])
        self
      end

      private

      attr_reader :relation

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
          :winning_user_id,
          :is_adult,
          :is_marketplace
        )
      end
    end
  end
end
