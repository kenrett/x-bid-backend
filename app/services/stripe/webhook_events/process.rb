module Stripe
  module WebhookEvents
    class Process
      SUPPORTED_TYPES = [
        "payment_intent.succeeded",
        "payment_intent.payment_failed",
        "charge.refunded",
        "checkout.session.completed"
      ].freeze

      def self.call(event:)
        new(event: event).call
      end

      def initialize(event:)
        @event = event
      end

      def call
        AppLogger.log(
          event: "stripe.webhook.received",
          stripe_event_id: event.respond_to?(:id) ? event.id : nil,
          stripe_event_type: event.respond_to?(:type) ? event.type : nil
        )
        return ServiceResult.ok(code: :ignored, message: "Unhandled event type: #{event.type}") unless supported_event?

        stripe_event = ensure_stripe_event_record!

        stripe_event.with_lock do
          return duplicate_result if stripe_event.processed_at.present?

          result = dispatch_event
          stripe_event.update!(processed_at: Time.current) if result.ok?
          result
        end
      rescue ActiveRecord::RecordNotUnique
        retry
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
        when "charge.refunded"
          handle_charge_refunded
        when "checkout.session.completed"
          handle_checkout_session_completed
        else
          ServiceResult.ok(code: :ignored, message: "Unhandled event type: #{event.type}")
        end
      end

      def handle_checkout_session_completed
        session = stripe_object_data
        session_hash =
          if session.is_a?(Hash)
            session
          elsif session.respond_to?(:to_hash)
            session.to_hash
          elsif session.respond_to?(:as_json)
            session.as_json
          else
            {}
          end

        session_data = (session_hash || {}).with_indifferent_access

        payment_status = session_data[:payment_status].to_s
        return ServiceResult.ok(code: :ignored, message: "Checkout session not paid", data: { payment_status: payment_status }) unless payment_status == "paid"

        metadata = (session_data[:metadata] || {}).with_indifferent_access
        user_id = metadata[:user_id]
        bid_pack_id = metadata[:bid_pack_id]
        purchase_id = metadata[:purchase_id]
        return ServiceResult.fail("Missing metadata on checkout session", code: :missing_metadata) if user_id.blank? || bid_pack_id.blank?

        user = User.find_by(id: user_id)
        bid_pack = BidPack.find_by(id: bid_pack_id)
        return ServiceResult.fail("User not found for checkout session", code: :user_not_found) unless user
        return ServiceResult.fail("Bid pack not found for checkout session", code: :bid_pack_not_found) unless bid_pack

        stripe_event_id = event.respond_to?(:id) ? event.id : nil
        checkout_session_id = session_data[:id].presence
        stripe_payment_intent_id = session_data[:payment_intent].presence

        if purchase_id.present?
          purchase = Purchase.find_by(id: purchase_id)
          return ServiceResult.fail("Purchase not found for checkout session", code: :not_found) unless purchase
          if purchase.user_id != user.id || purchase.bid_pack_id != bid_pack.id
            AppLogger.log(
              event: "stripe.checkout.purchase_mismatch",
              level: :error,
              purchase_id: purchase.id,
              user_id: user.id,
              bid_pack_id: bid_pack.id,
              stripe_event_id: stripe_event_id,
              checkout_session_id: checkout_session_id,
              payment_intent_id: stripe_payment_intent_id
            )
            return ServiceResult.fail("Purchase mismatch for checkout session", code: :invalid_state)
          end

          purchase.update!(
            stripe_checkout_session_id: purchase.stripe_checkout_session_id.presence || checkout_session_id,
            stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || stripe_payment_intent_id
          )
        end

        amount_total = session_data[:amount_total]
        amount_cents = amount_total.present? ? amount_total.to_i : (bid_pack.price.to_d * 100).to_i
        currency = (session_data[:currency].presence || "usd").to_s

        result = Payments::ApplyBidPackPurchase.call!(
          user: user,
          bid_pack: bid_pack,
          stripe_checkout_session_id: checkout_session_id,
          stripe_payment_intent_id: stripe_payment_intent_id,
          stripe_event_id: stripe_event_id,
          amount_cents: amount_cents,
          currency: currency,
          source: "stripe_webhook_checkout_session_completed"
        )

        unless result.ok?
          AppLogger.log(
            event: "stripe.checkout_session_completed.purchase_not_created",
            level: :error,
            stripe_event_id: stripe_event_id,
            checkout_session_id: checkout_session_id,
            payment_intent_id: stripe_payment_intent_id,
            code: result.code,
            message: result.message
          )
          raise "Stripe checkout session completed but purchase was not created"
        end

        purchase = result.purchase
        unless purchase&.persisted?
          AppLogger.log(
            event: "stripe.checkout_session_completed.purchase_not_created",
            level: :error,
            stripe_event_id: stripe_event_id,
            checkout_session_id: checkout_session_id,
            payment_intent_id: stripe_payment_intent_id
          )
          raise "Stripe checkout session completed but purchase was not created"
        end

        log_payment_applied(user:, bid_pack:, purchase:, payment_intent_id: stripe_payment_intent_id)
        result
      end

      def handle_payment_intent_succeeded
        data = stripe_object_data
        metadata = (data["metadata"] || data[:metadata] || {}).with_indifferent_access
        @payment_intent_id = data[:id] || data["id"] || data[:payment_intent] || data["payment_intent"]

        if metadata[:auction_settlement_id].present?
          return handle_auction_settlement_payment_succeeded(metadata:, payment_intent_id: payment_intent_id)
        end

        purchase_id = metadata[:purchase_id]
        user = User.find_by(id: metadata[:user_id])
        bid_pack = BidPack.find_by(id: metadata[:bid_pack_id])
        return ServiceResult.fail("User not found for Stripe payment", code: :user_not_found) unless user
        return ServiceResult.fail("Bid pack not found for Stripe payment", code: :bid_pack_not_found) unless bid_pack

        if purchase_id.present?
          purchase = Purchase.find_by(id: purchase_id)
          return ServiceResult.fail("Purchase not found for Stripe payment", code: :not_found) unless purchase
          if purchase.user_id != user.id || purchase.bid_pack_id != bid_pack.id
            AppLogger.log(
              event: "stripe.payment.purchase_mismatch",
              level: :error,
              purchase_id: purchase.id,
              user_id: user.id,
              bid_pack_id: bid_pack.id,
              stripe_event_id: event.id,
              payment_intent_id: payment_intent_id
            )
            return ServiceResult.fail("Purchase mismatch for Stripe payment", code: :invalid_state)
          end

          purchase.update!(stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || payment_intent_id)
        end

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

      def handle_charge_refunded
        charge = stripe_object_data
        @payment_intent_id = charge[:payment_intent] || charge["payment_intent"]
        return ServiceResult.fail("Missing payment intent on charge refund event", code: :missing_payment_intent) if payment_intent_id.blank?

        purchase = Purchase.find_by(stripe_payment_intent_id: payment_intent_id)
        unless purchase
          AppLogger.log(event: "stripe.refund.purchase_not_found", level: :error, payment_intent_id: payment_intent_id, stripe_event_id: event.id)
          return ServiceResult.fail("Purchase not found for Stripe refund", code: :not_found)
        end

        refund_total_cents = (charge[:amount_refunded] || charge["amount_refunded"] || 0).to_i
        return ServiceResult.ok(code: :ignored, message: "Refund amount is zero", data: { purchase_id: purchase.id }) if refund_total_cents <= 0

        if refund_total_cents > purchase.amount_cents.to_i
          AppLogger.log(
            event: "stripe.refund.amount_exceeds_purchase",
            level: :error,
            payment_intent_id: payment_intent_id,
            stripe_event_id: event.id,
            purchase_id: purchase.id,
            refund_total_cents: refund_total_cents,
            purchase_amount_cents: purchase.amount_cents.to_i
          )
          refund_total_cents = purchase.amount_cents.to_i
        end

        return ServiceResult.ok(code: :already_processed, message: "Purchase already refunded", data: { purchase_id: purchase.id }) if purchase.refunded_cents.to_i.positive?
        return ServiceResult.ok(code: :already_processed, message: "Refund already recorded", data: { purchase_id: purchase.id }) if refund_money_event_exists?(purchase)

        refund_id = extract_refund_id_from_charge(charge)

        result = Payments::ApplyPurchaseRefund.call!(
          purchase: purchase,
          refunded_total_cents: refund_total_cents,
          refund_id: refund_id,
          reason: nil,
          source: "stripe_webhook"
        )

        return result unless result.ok?

        ServiceResult.ok(code: result.code, message: "Refund applied", data: { purchase: purchase })
      end

      def ensure_stripe_event_record!
        StripeEvent.find_or_create_by!(stripe_event_id: event.id) do |record|
          record.event_type = event.type
          record.payload = event_payload
        end.tap do |record|
          next if record.processed_at.present?

          missing_payload = record.payload.blank? || record.payload == {}
          missing_type = record.event_type.blank?
          if missing_payload || missing_type
            record.update_columns(
              event_type: (record.event_type.presence || event.type),
              payload: (missing_payload ? event_payload : record.payload),
              updated_at: Time.current
            )
          end
        end
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
        AppLogger.log(
          event: "stripe.webhook.duplicate",
          stripe_event_id: event.respond_to?(:id) ? event.id : nil,
          stripe_event_type: event.respond_to?(:type) ? event.type : nil
        )
        ServiceResult.ok(code: :duplicate, message: "Event already processed", data: { idempotent: true })
      end

      def extract_refund_id_from_charge(charge)
        refunds = charge[:refunds] || charge["refunds"] || {}
        refunds_data = refunds[:data] || refunds["data"] || []
        last = refunds_data.last
        last[:id] || last["id"]
      rescue
        nil
      end

      def refund_money_event_exists?(purchase)
        MoneyEvent.exists?(
          event_type: :refund,
          source_type: "StripePaymentIntent",
          source_id: purchase.stripe_payment_intent_id.to_s
        )
      end
    end
  end
end
