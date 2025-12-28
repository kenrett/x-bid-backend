module Stripe
  module WebhookEvents
    class Process
      SUPPORTED_TYPES = [ "payment_intent.succeeded", "payment_intent.payment_failed" ].freeze

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
      attr_reader :persisted_event
      attr_reader :payment_intent_id

      def supported_event?
        SUPPORTED_TYPES.include?(event.type)
      end

      def dispatch_event
        case event.type
        when "payment_intent.succeeded"
          handle_payment_intent_succeeded
        when "payment_intent.payment_failed"
          handle_payment_intent_failed
        else
          ServiceResult.ok(code: :ignored, message: "Unhandled event type: #{event.type}")
        end
      end

      def handle_payment_intent_succeeded
        data = stripe_object_data
        metadata = (data["metadata"] || data[:metadata] || {}).with_indifferent_access
        @payment_intent_id = data[:id] || data["id"] || data[:payment_intent] || data["payment_intent"]

        if metadata[:auction_settlement_id].present?
          return handle_auction_settlement_payment_succeeded(metadata:, payment_intent_id: payment_intent_id)
        end

        user = User.find_by(id: metadata[:user_id])
        bid_pack = BidPack.find_by(id: metadata[:bid_pack_id])
        return ServiceResult.fail("User not found for Stripe payment", code: :user_not_found) unless user
        return ServiceResult.fail("Bid pack not found for Stripe payment", code: :bid_pack_not_found) unless bid_pack

        amount_cents = data[:amount_received] || data["amount_received"] || (bid_pack.price.to_d * 100).to_i
        currency = (data[:currency] || data["currency"] || "usd").to_s
        stripe_event_id = event.respond_to?(:id) ? event.id : nil

        result = Payments::ApplyBidPackPurchase.call!(
          user: user,
          bid_pack: bid_pack,
          stripe_checkout_session_id: nil,
          stripe_payment_intent_id: payment_intent_id,
          stripe_event_id: stripe_event_id,
          amount_cents: amount_cents,
          currency: currency,
          source: "stripe_webhook"
        )
        unless result.ok?
          AppLogger.log(
            event: "stripe.payment_succeeded.purchase_not_created",
            level: :error,
            stripe_event_id: stripe_event_id,
            payment_intent_id: payment_intent_id,
            code: result.code,
            message: result.message
          )
          raise "Stripe payment succeeded but purchase was not created"
        end

        purchase = result.purchase
        unless purchase&.persisted?
          AppLogger.log(
            event: "stripe.payment_succeeded.purchase_not_created",
            level: :error,
            stripe_event_id: stripe_event_id,
            payment_intent_id: payment_intent_id
          )
          raise "Stripe payment succeeded but purchase was not created"
        end
        log_payment_applied(user:, bid_pack:, purchase:, payment_intent_id:)

        result
      end

      def handle_payment_intent_failed
        data = stripe_object_data
        metadata = (data["metadata"] || data[:metadata] || {}).with_indifferent_access
        @payment_intent_id = data[:id] || data["id"] || data[:payment_intent] || data["payment_intent"]

        return handle_auction_settlement_payment_failed(metadata:, payment_intent_id: payment_intent_id) if metadata[:auction_settlement_id].present?

        ServiceResult.ok(code: :ignored, message: "Payment failure ignored for non-settlement intent")
      end

      def persist_event!
        @persisted_event ||= StripeEvent.create!(
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

      def handle_auction_settlement_payment_succeeded(metadata:, payment_intent_id:)
        settlement = AuctionSettlement.find_by(id: metadata[:auction_settlement_id])
        return ServiceResult.fail("Settlement not found for Stripe payment", code: :not_found) unless settlement
        return ServiceResult.ok(code: :already_processed, message: "Settlement already paid", data: { settlement: settlement }) if settlement.paid?

        settlement.mark_paid!(payment_intent_id: payment_intent_id)
        AppLogger.log(
          event: "auction.payment_succeeded",
          auction_id: settlement.auction_id,
          settlement_id: settlement.id,
          winning_user_id: settlement.winning_user_id,
          payment_intent_id: payment_intent_id
        )

        ServiceResult.ok(code: :paid, message: "Settlement paid", data: { settlement: settlement })
      end

      def handle_auction_settlement_payment_failed(metadata:, payment_intent_id:)
        settlement = AuctionSettlement.find_by(id: metadata[:auction_settlement_id])
        return ServiceResult.fail("Settlement not found for Stripe payment", code: :not_found) unless settlement
        return ServiceResult.ok(code: :already_processed, message: "Settlement already closed", data: { settlement: settlement }) if settlement.paid? || settlement.cancelled?

        settlement.mark_payment_failed!(reason: "stripe_payment_failed")
        AppLogger.log(
          event: "auction.payment_failed",
          auction_id: settlement.auction_id,
          settlement_id: settlement.id,
          winning_user_id: settlement.winning_user_id,
          payment_intent_id: payment_intent_id
        )

        ServiceResult.ok(code: :payment_failed, message: "Settlement payment failed", data: { settlement: settlement })
      end

      def log_error(exception)
        AppLogger.error(
          event: "stripe.webhook.error",
          error: exception,
          payment_intent_id: payment_intent_id,
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
