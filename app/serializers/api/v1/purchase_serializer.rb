module Api
  module V1
    class PurchaseSerializer < ActiveModel::Serializer
      attributes :id,
                 :created_at,
                 :status,
                 :amount_cents,
                 :currency,
                 :receipt_status,
                 :receipt_url,
                 :stripe_checkout_session_id,
                 :stripe_payment_intent_id,
                 :stripe_charge_id,
                 :stripe_event_id,
                 :bid_pack

      def receipt_url
        object.receipt_status == "available" ? object.receipt_url : nil
      end

      def bid_pack
        pack = object.bid_pack
        return nil unless pack

        {
          id: pack.id,
          name: pack.name,
          credits: pack.bids,
          price_cents: (pack.price.to_d * 100).to_i
        }
      end
    end
  end
end
