module Api
  module V1
    class WonAuctionDetailSerializer < ActiveModel::Serializer
      attributes :auction_id,
                 :auction_title,
                 :final_price,
                 :ended_at,
                 :settlement_id,
                 :fulfillment_status,
                 :winning_bid,
                 :fulfillment

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
        object.fulfillment_status
      end

      def winning_bid
        bid = object.winning_bid
        return nil unless bid

        {
          id: bid.id,
          user_id: bid.user_id,
          amount: bid.amount,
          auto: bid.auto,
          created_at: bid.created_at
        }
      end

      def fulfillment
        {
          address: object.fulfillment_address,
          shipping_cost: object.shipping_cost,
          carrier: object.shipping_carrier,
          tracking_number: object.tracking_number
        }
      end
    end
  end
end
