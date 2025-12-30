module Api
  module V1
    class PurchaseSerializer < ActiveModel::Serializer
      attributes :id,
                 :created_at,
                 :payment_status,
                 :status,
                 :amount_cents,
                 :currency,
                 :credits_added,
                 :receipt_status,
                 :receipt_url,
                 :ledger_grant_entry_id,
                 :stripe_checkout_session_id,
                 :stripe_payment_intent_id,
                 :stripe_charge_id,
                 :stripe_event_id,
                 :bid_pack

      def payment_status
        object.status
      end

      def credits_added
        object.bid_pack&.bids
      end

      def receipt_url
        object.receipt_status == "available" ? object.receipt_url : nil
      end

      def ledger_grant_entry_id
        object.ledger_grant_credit_transaction_id
      end

      def bid_pack
        pack = object.bid_pack
        return nil unless pack

        {
          id: pack.id,
          name: pack.name,
          sku: pack.respond_to?(:sku) ? pack.sku : nil,
          credits: pack.bids,
          price_cents: (pack.price.to_d * 100).to_i
        }
      end
    end
  end
end
