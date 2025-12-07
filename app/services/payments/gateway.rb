module Payments
  class Gateway
    GatewayResponse = Struct.new(:success?, :refund_id, :raw_response, :error_code, :error_message, keyword_init: true)

    class << self
      def issue_refund(payment:, amount_cents:, reason: nil)
        return GatewayResponse.new(success?: false, error_code: :missing_payment_intent, error_message: "Payment intent missing") if payment.stripe_payment_intent_id.blank?

        refund = Stripe::Refund.create({ payment_intent: payment.stripe_payment_intent_id, amount: amount_cents, reason: reason.presence }.compact)
        GatewayResponse.new(success?: true, refund_id: refund.id, raw_response: safe_hash(refund))
      rescue Stripe::StripeError => e
        GatewayResponse.new(success?: false, error_code: e.respond_to?(:code) ? e.code : e.class.name, error_message: e.message)
      rescue => e
        GatewayResponse.new(success?: false, error_code: e.class.name, error_message: e.message)
      end

      private

      def safe_hash(refund)
        return refund if refund.is_a?(Hash)
        refund.respond_to?(:to_hash) ? refund.to_hash : refund.as_json
      rescue
        { inspected: refund.inspect }
      end
    end
  end
end
