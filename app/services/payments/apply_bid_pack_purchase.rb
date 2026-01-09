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

            # Receipt handling decision (Option A — Real receipts):
            # We persist the Stripe-hosted receipt URL only when Stripe provides it (never synthesized).
            # This field is intentionally nullable because a receipt URL may not exist for every payment method / flow.
            receipt_url, receipt_status, stripe_charge_id = receipt_lookup_for(purchase:, stripe_payment_intent_id: stripe_payment_intent_id)

            purchase.assign_attributes(
              user: user,
              bid_pack: bid_pack,
              amount_cents: amount_cents.to_i,
              currency: currency.to_s,
              storefront_key: purchase.storefront_key.presence || Current.storefront_key.to_s.presence,
              stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || stripe_payment_intent_id.presence,
              stripe_checkout_session_id: purchase.stripe_checkout_session_id.presence || stripe_checkout_session_id.presence,
              stripe_event_id: purchase.stripe_event_id.presence || stripe_event_id.presence,
              stripe_charge_id: purchase.stripe_charge_id.presence || stripe_charge_id.presence,
              receipt_url: receipt_url,
              receipt_status: receipt_status,
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
                storefront_key: purchase.storefront_key.presence || Current.storefront_key.to_s.presence,
                stripe_payment_intent_id: purchase.stripe_payment_intent_id.presence || stripe_payment_intent_id.presence,
                stripe_checkout_session_id: purchase.stripe_checkout_session_id.presence || stripe_checkout_session_id.presence,
                stripe_event_id: purchase.stripe_event_id.presence || stripe_event_id.presence,
                stripe_charge_id: purchase.stripe_charge_id.presence || stripe_charge_id.presence,
                receipt_url: receipt_url,
                receipt_status: receipt_status,
                status: "completed"
              )
              purchase.save!
            end

            enforce_one_purchase_per_payment_intent!(
              purchase: purchase,
              stripe_payment_intent_id: stripe_payment_intent_id
            )

            record_purchase_money_event!(
              user: user,
              amount_cents: amount_cents,
              currency: currency,
              stripe_payment_intent_id: stripe_payment_intent_id,
              storefront_key: purchase.storefront_key,
              occurred_at: Time.current,
              metadata: {
                purchase_id: purchase.id,
                stripe_event_id: stripe_event_id,
                stripe_checkout_session_id: stripe_checkout_session_id,
                source: source
              }
            )

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
              storefront_key: purchase.storefront_key,
              stripe_payment_intent_id: stripe_payment_intent_id,
              stripe_checkout_session_id: stripe_checkout_session_id,
              metadata: { source: source }
            )

              credit_transaction = CreditTransaction.find_by!(idempotency_key: credit_idempotency_key)
              idempotent = !purchase_was_new && credit_already_exists

              if purchase.ledger_grant_credit_transaction_id.nil?
                purchase.update!(ledger_grant_credit_transaction_id: credit_transaction.id)
              end

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
              AuditLogger.log(
                action: "payment.applied",
                actor: (Current.user_id.to_s == user.id.to_s ? user : nil),
                user: user,
                session_token_id: Current.session_token_id,
                payload: {
                  purchase_id: purchase.id,
                  bid_pack_id: bid_pack.id,
                  amount_cents: amount_cents.to_i,
                  currency: currency.to_s,
                  stripe_payment_intent_id: stripe_payment_intent_id,
                  stripe_checkout_session_id: stripe_checkout_session_id,
                  stripe_event_id: stripe_event_id,
                  idempotent: idempotent,
                  source: source
                }.compact
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
        PurchaseReceiptEmailJob.perform_later(result.purchase.id, storefront_key: result.purchase.storefront_key)
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
        AppLogger.error(
          event: "payments.apply_purchase.error",
          error: e,
          user_id: user&.id,
          bid_pack_id: bid_pack&.id,
          stripe_payment_intent_id: stripe_payment_intent_id,
          stripe_checkout_session_id: stripe_checkout_session_id,
          stripe_event_id: stripe_event_id,
          source: source
        )
        ServiceResult.fail("Validation error: #{e.message}", code: :validation_error, record: e.record)
      rescue => e
        AppLogger.error(
          event: "payments.apply_purchase.error",
          error: e,
          user_id: user&.id,
          bid_pack_id: bid_pack&.id,
          stripe_payment_intent_id: stripe_payment_intent_id,
          stripe_checkout_session_id: stripe_checkout_session_id,
          stripe_event_id: stripe_event_id,
          source: source
        )
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

      def receipt_lookup_for(purchase:, stripe_payment_intent_id:)
        return [ purchase.receipt_url, :available, purchase.stripe_charge_id ] if purchase.receipt_url.present?
        return [ nil, purchase.receipt_status.to_sym, purchase.stripe_charge_id ] if purchase.receipt_status != "pending"

        status, url, charge_id = Payments::StripeReceiptLookup.lookup(payment_intent_id: stripe_payment_intent_id)
        [ url, status, charge_id ]
      end

      def record_purchase_money_event!(user:, amount_cents:, currency:, stripe_payment_intent_id:, storefront_key:, occurred_at:, metadata:)
        return if stripe_payment_intent_id.blank?

        MoneyEvent.transaction(requires_new: true) do
          MoneyEvent.create!(
            user: user,
            event_type: :purchase,
            amount_cents: amount_cents.to_i,
            currency: currency.to_s,
            source_type: "StripePaymentIntent",
            source_id: stripe_payment_intent_id.to_s,
            occurred_at: occurred_at,
            metadata: metadata,
            storefront_key: storefront_key
          )
        end
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def enforce_one_purchase_per_payment_intent!(purchase:, stripe_payment_intent_id:)
        return if stripe_payment_intent_id.blank?
        return if purchase.blank? || !purchase.persisted?

        if Purchase.where(stripe_payment_intent_id: stripe_payment_intent_id).where.not(id: purchase.id).exists?
          AppLogger.log(
            event: "payments.purchase_uniqueness_violation",
            level: :error,
            purchase_id: purchase.id,
            user_id: purchase.user_id,
            stripe_payment_intent_id: stripe_payment_intent_id
          )
          raise "Stripe payment intent maps to multiple purchases"
        end
      end
    end
  end
end
