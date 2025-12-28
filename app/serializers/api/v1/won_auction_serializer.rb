module Api
  module V1
    class WonAuctionSerializer < ActiveModel::Serializer
      attributes :auction_id,
                 :auction_title,
                 :final_price,
                 :ended_at,
                 :settlement_id,
                 :fulfillment_status

      def auction_id
        object.auction_id
      end

      def auction_title
        object.auction&.title
      end

      def settlement_id
        object.id
      end

      def fulfillment_status
        object.auction_fulfillment&.status || "pending"
      end
    end
  end
end
