require "securerandom"

module Billing
  class PurchaseBidPack
    def initialize(user:, bid_pack:, payment_intent_id: nil, checkout_session_id: nil)
      @user = user
      @bid_pack = bid_pack
      @payment_intent_id = payment_intent_id
      @checkout_session_id = checkout_session_id
    end

    def call
      return ServiceResult.fail("Payment reference required", code: :missing_payment_reference) unless payment_reference_present?

      ActiveRecord::Base.transaction do
        purchase = find_purchase
        if purchase&.status.in?(%w[applied completed])
          return ServiceResult.ok(code: :already_processed, message: "Payment already applied", data: { purchase: purchase, idempotent: true })
        end

        purchase ||= Purchase.new
        purchase.assign_attributes(
          user: @user,
          bid_pack: @bid_pack,
          amount_cents: amount_cents,
          currency: "usd",
          stripe_checkout_session_id: @checkout_session_id,
          stripe_payment_intent_id: @payment_intent_id,
          status: "applied",
          applied_at: Time.current
        )
        purchase.save!

        Credits::Apply.apply!(
          user: @user,
          reason: "bid_pack_purchase",
          amount: @bid_pack.bids,
          purchase: purchase,
          stripe_payment_intent_id: @payment_intent_id,
          stripe_checkout_session_id: @checkout_session_id,
          idempotency_key: idempotency_key,
          metadata: { source: "billing_purchase_bid_pack" }
        )

        if purchase.ledger_grant_credit_transaction_id.nil?
          grant = CreditTransaction.find_by!(idempotency_key: idempotency_key)
          purchase.update!(ledger_grant_credit_transaction_id: grant.id)
        end
        AppLogger.log(
          event: "billing.purchase_bid_pack",
          user_id: @user.id,
          bid_pack_id: @bid_pack.id,
          purchase_id: purchase.id,
          payment_intent_id: @payment_intent_id,
          checkout_session_id: @checkout_session_id,
          bids: @bid_pack.bids
        )
        ServiceResult.ok(code: :processed, message: "Bid pack purchased successfully!", data: { bid_pack: @bid_pack, bids_added: @bid_pack.bids })
      end
    rescue ActiveRecord::RecordNotUnique
      purchase = find_purchase
      return ServiceResult.ok(code: :already_processed, message: "Payment already applied", data: { purchase: purchase, idempotent: true }) if purchase

      raise
    rescue ActiveRecord::RecordInvalid => e
      AppLogger.error(event: "billing.purchase_bid_pack.error", error: e, user_id: @user.id, bid_pack_id: @bid_pack.id)
      ServiceResult.fail("Validation error: #{e.message}", code: :validation_error)
    rescue => e
      AppLogger.error(event: "billing.purchase_bid_pack.error", error: e, user_id: @user.id, bid_pack_id: @bid_pack.id)
      ServiceResult.fail("An unexpected error occurred: #{e.message}", code: :unexpected_error)
    end

    private

    def payment_reference_present?
      @payment_intent_id.present? || @checkout_session_id.present?
    end

    def find_purchase
      if @payment_intent_id.present?
        purchase = Purchase.find_by(stripe_payment_intent_id: @payment_intent_id)
        return purchase if purchase
      end
      return Purchase.find_by(stripe_checkout_session_id: @checkout_session_id) if @checkout_session_id.present?

      nil
    end

    def amount_cents
      (@bid_pack.price.to_d * 100).to_i
    end

    def idempotency_key
      return "stripe:payment_intent:#{@payment_intent_id}" if @payment_intent_id.present?
      return "stripe:checkout_session:#{@checkout_session_id}" if @checkout_session_id.present?

      SecureRandom.uuid
    end
  end
end
