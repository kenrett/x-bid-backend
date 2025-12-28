module Payments
  class ApplyBidPackPurchase
    class << self
      def call!(user:, bid_pack:, stripe_checkout_session_id:, stripe_payment_intent_id:, stripe_event_id:, amount_cents:, currency:, source:)
        raise ArgumentError, "User must be provided" unless user
        raise ArgumentError, "Bid pack must be provided" unless bid_pack
        raise ArgumentError, "Currency must be provided" if currency.blank?
        raise ArgumentError, "Source must be provided" if source.blank?
        raise ArgumentError, "Amount cents must be non-negative" if amount_cents.to_i.negative?
        raise ArgumentError, "Stripe identifier required" if stripe_payment_intent_id.blank? && stripe_checkout_session_id.blank? && stripe_event_id.blank?

        result = nil
        ActiveRecord::Base.transaction do
          user.with_lock do
            purchase, purchase_was_new = find_or_build_purchase(
              user: user,
              stripe_payment_intent_id: stripe_payment_intent_id,
              stripe_checkout_session_id: stripe_checkout_session_id,
              stripe_event_id: stripe_event_id
            )

            if purchase.persisted? && purchase.bid_pack_id.present? && purchase.bid_pack_id != bid_pack.id
              raise ArgumentError, "Bid pack mismatch for purchase"
            end

            purchase.assign_attributes(
              user: user,
              bid_pack: bid_pack,
              amount_cents: amount_cents.to_i,
              currency: currency.to_s,
              stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || stripe_payment_intent_id.presence,
              stripe_checkout_session_id: purchase.stripe_checkout_session_id.presence || stripe_checkout_session_id.presence,
              stripe_event_id: purchase.stripe_event_id.presence || stripe_event_id.presence,
              status: "completed"
            )

            begin
              purchase.save!
            rescue ActiveRecord::RecordNotUnique
              purchase, purchase_was_new = find_or_build_purchase(
                user: user,
                stripe_payment_intent_id: stripe_payment_intent_id,
                stripe_checkout_session_id: stripe_checkout_session_id,
                stripe_event_id: stripe_event_id
              )
              purchase.assign_attributes(
                user: user,
                bid_pack: bid_pack,
                amount_cents: amount_cents.to_i,
                currency: currency.to_s,
                stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || stripe_payment_intent_id.presence,
                stripe_checkout_session_id: purchase.stripe_checkout_session_id.presence || stripe_checkout_session_id.presence,
                stripe_event_id: purchase.stripe_event_id.presence || stripe_event_id.presence,
                status: "completed"
              )
              purchase.save!
            end

            credit_idempotency_key = "purchase:#{purchase.id}:grant"
            credit_already_exists = CreditTransaction.exists?(idempotency_key: credit_idempotency_key)

            stripe_event = StripeEvent.find_by(stripe_event_id: stripe_event_id) if stripe_event_id.present?

            Credits::Apply.apply!(
              user: user,
              reason: "bid_pack_purchase",
              amount: bid_pack.bids,
              idempotency_key: credit_idempotency_key,
              purchase: purchase,
              stripe_event: stripe_event,
              stripe_payment_intent_id: stripe_payment_intent_id,
              stripe_checkout_session_id: stripe_checkout_session_id,
              metadata: { source: source }
            )

            credit_transaction = CreditTransaction.find_by!(idempotency_key: credit_idempotency_key)
            idempotent = !purchase_was_new && credit_already_exists

            AppLogger.log(
              event: "payments.apply_purchase",
              user_id: user.id,
              purchase_id: purchase.id,
              bid_pack_id: bid_pack.id,
              stripe_payment_intent_id: stripe_payment_intent_id,
              stripe_checkout_session_id: stripe_checkout_session_id,
              stripe_event_id: stripe_event_id,
              idempotent: idempotent,
              source: source
            )

            result = ServiceResult.ok(
              code: idempotent ? :already_processed : :processed,
              message: idempotent ? "Payment already applied" : "Payment applied",
              data: { purchase: purchase, credit_transaction: credit_transaction },
              idempotent: idempotent
            )
          end
        end

        unless result&.idempotent
          PurchaseReceiptEmailJob.perform_later(result.purchase.id)
          Notification.create!(
            user: user,
            kind: :purchase_completed,
            data: {
              purchase_id: result.purchase.id,
              bid_pack_id: result.purchase.bid_pack_id,
              bid_pack_name: bid_pack.name,
              credits_granted: bid_pack.bids,
              amount_cents: result.purchase.amount_cents,
              currency: result.purchase.currency
            }
          )
        end
        result
      rescue ActiveRecord::RecordInvalid => e
        AppLogger.error(event: "payments.apply_purchase.error", error: e, user_id: user&.id, bid_pack_id: bid_pack&.id, source: source)
        ServiceResult.fail("Validation error: #{e.message}", code: :validation_error, record: e.record)
      rescue => e
        AppLogger.error(event: "payments.apply_purchase.error", error: e, user_id: user&.id, bid_pack_id: bid_pack&.id, source: source)
        ServiceResult.fail("Unable to apply purchase", code: :processing_error)
      end

      private

      def find_or_build_purchase(user:, stripe_payment_intent_id:, stripe_checkout_session_id:, stripe_event_id:)
        purchase = nil

        if stripe_payment_intent_id.present?
          purchase = Purchase.find_by(stripe_payment_intent_id: stripe_payment_intent_id)
        end

        if purchase.nil? && stripe_checkout_session_id.present?
          purchase = Purchase.find_by(stripe_checkout_session_id: stripe_checkout_session_id)
        end

        if purchase.nil? && stripe_event_id.present?
          purchase = Purchase.find_by(stripe_event_id: stripe_event_id)
        end

        if purchase
          raise ArgumentError, "Purchase user mismatch" if purchase.user_id != user.id
          return [ purchase, false ]
        end

        [ Purchase.new, true ]
      end
    end
  end
end
