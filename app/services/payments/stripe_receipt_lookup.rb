module Payments
  class StripeReceiptLookup
    class << self
      # Returns [status, receipt_url, stripe_charge_id]
      # - status: :available, :unavailable, :pending
      def lookup(payment_intent_id:)
        return [ :pending, nil, nil ] if payment_intent_id.blank?
        return [ :pending, nil, nil ] if Stripe.api_key.blank?

        receipt_url, stripe_charge_id = fetch_stripe_receipt_info(payment_intent_id: payment_intent_id)
        return [ :available, receipt_url, stripe_charge_id ] if receipt_url.present?

        # If Stripe responded successfully but no receipt URL exists, we treat this as final.
        [ :unavailable, nil, stripe_charge_id ]
      rescue Stripe::StripeError => e
        AppLogger.error(
          event: "payments.apply_purchase.receipt_url_error",
          error: e,
          stripe_payment_intent_id: payment_intent_id
        )
        [ :pending, nil, nil ]
      end

      private

      def fetch_stripe_receipt_info(payment_intent_id:)
        return [ nil, nil ] if payment_intent_id.blank?
        return [ nil, nil ] if Stripe.api_key.blank?

        payment_intent = Stripe::PaymentIntent.retrieve({ id: payment_intent_id, expand: [ "latest_charge" ] })

        latest_charge = payment_intent.respond_to?(:latest_charge) ? payment_intent.latest_charge : nil
        charge_id = latest_charge&.respond_to?(:id) ? latest_charge.id : (latest_charge.is_a?(String) ? latest_charge : nil)
        receipt_url = latest_charge&.respond_to?(:receipt_url) ? latest_charge.receipt_url : nil
        return [ receipt_url, charge_id ] if receipt_url.present? || charge_id.present?

        if latest_charge.is_a?(String)
          charge = Stripe::Charge.retrieve(latest_charge)
          url = charge.respond_to?(:receipt_url) ? charge.receipt_url : nil
          charge_id = charge.respond_to?(:id) ? charge.id : latest_charge
          return [ url, charge_id ]
        end

        if payment_intent.respond_to?(:charges) && payment_intent.charges.respond_to?(:data)
          charge = payment_intent.charges.data.first
          url = charge&.respond_to?(:receipt_url) ? charge.receipt_url : nil
          charge_id = charge&.respond_to?(:id) ? charge.id : nil
          return [ url, charge_id ]
        end

        [ nil, nil ]
      end
    end
  end
end
