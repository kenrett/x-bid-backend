module Stripe
  module WebhookEvents
    class Process
      SUPPORTED_TYPES = [ "payment_intent.succeeded" ].freeze

      def self.call(event:)
        new(event: event).call
      end

      def initialize(event:)
        @event = event
      end

      def call
        return ServiceResult.ok(code: :ignored, message: "Unhandled event type: #{event.type}") unless supported_event?

        persist_event!
        dispatch_event
      rescue ActiveRecord::RecordNotUnique
        duplicate_result
      rescue ActiveRecord::RecordInvalid => e
        raise unless duplicate_event_error?(e)

        duplicate_result
      rescue => e
        log_error(e)
        ServiceResult.fail("Unable to process Stripe event", code: :processing_error)
      end

      private

      attr_reader :event

      def supported_event?
        SUPPORTED_TYPES.include?(event.type)
      end

      def dispatch_event
        case event.type
        when "payment_intent.succeeded"
          handle_payment_intent_succeeded
        else
          ServiceResult.ok(code: :ignored, message: "Unhandled event type: #{event.type}")
        end
      end

      def handle_payment_intent_succeeded
        data = stripe_object_data
        metadata = (data["metadata"] || data[:metadata] || {}).with_indifferent_access

        user = User.find_by(id: metadata[:user_id])
        bid_pack = BidPack.find_by(id: metadata[:bid_pack_id])
        return ServiceResult.fail("User not found for Stripe payment", code: :user_not_found) unless user
        return ServiceResult.fail("Bid pack not found for Stripe payment", code: :bid_pack_not_found) unless bid_pack

        payment_intent_id = data[:id] || data["id"] || data[:payment_intent] || data["payment_intent"]
        amount_cents = data[:amount_received] || data["amount_received"] || (bid_pack.price.to_d * 100).to_i
        currency = (data[:currency] || data["currency"] || "usd").to_s

        ActiveRecord::Base.transaction do
          user.with_lock do
            purchase = Purchase.find_by(stripe_payment_intent_id: payment_intent_id)
            return ServiceResult.ok(code: :already_processed, message: "Payment already applied", data: { purchase: purchase, idempotent: true }) if purchase&.status == "completed"

            purchase ||= Purchase.new
            purchase.assign_attributes(
              user: user,
              bid_pack: bid_pack,
              amount_cents: amount_cents,
              currency: currency,
              stripe_payment_intent_id: payment_intent_id,
              status: "completed"
            )
            purchase.save!

            user.update!(bid_credits: user.bid_credits + bid_pack.bids)
            log_payment_applied(user:, bid_pack:, purchase:, payment_intent_id:)

            ServiceResult.ok(code: :processed, message: "Payment applied", data: { purchase: purchase })
          end
        end
      end

      def persist_event!
        StripeEvent.create!(
          stripe_event_id: event.id,
          event_type: event.type,
          payload: event_payload,
          processed_at: Time.current
        )
      end

      def stripe_object_data
        if event.respond_to?(:data) && event.data.respond_to?(:object)
          event.data.object
        else
          event_payload.dig(:data, :object) || event_payload.dig("data", "object") || {}
        end
      end

      def event_payload
        return event.to_hash if event.respond_to?(:to_hash)
        return event.to_h if event.respond_to?(:to_h)
        return event.as_json if event.respond_to?(:as_json)

        {}
      end

      def log_payment_applied(user:, bid_pack:, purchase:, payment_intent_id:)
        AppLogger.log(
          event: "stripe.payment_succeeded",
          user_id: user.id,
          bid_pack_id: bid_pack.id,
          purchase_id: purchase.id,
          payment_intent_id: payment_intent_id,
          stripe_event_id: event.id,
          amount_cents: purchase.amount_cents,
          currency: purchase.currency
        )
      end

      def log_error(exception)
        AppLogger.error(
          event: "stripe.webhook.error",
          error: exception,
          stripe_event_id: event.respond_to?(:id) ? event.id : nil,
          stripe_event_type: event.respond_to?(:type) ? event.type : nil
        )
      end

      def duplicate_result
        ServiceResult.ok(code: :duplicate, message: "Event already processed", data: { idempotent: true })
      end

      def duplicate_event_error?(error)
        record = error.record
        record.is_a?(StripeEvent)
      end
    end
  end
end
