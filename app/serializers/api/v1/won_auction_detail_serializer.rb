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
        object.auction_fulfillment&.status || "pending"
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
        fulfillment = object.auction_fulfillment
        return { address: nil, shipping_cost: nil, carrier: nil, tracking_number: nil } unless fulfillment

        shipping_cost = fulfillment.shipping_cost_cents.present? ? (BigDecimal(fulfillment.shipping_cost_cents) / 100) : nil

        {
          address: fulfillment.shipping_address,
          shipping_cost: shipping_cost,
          carrier: fulfillment.shipping_carrier,
          tracking_number: fulfillment.tracking_number
        }
      end
    end
  end
end
