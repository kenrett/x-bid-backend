class PurchaseReceiptBackfillJob < ApplicationJob
  queue_as :default

  WINDOW_DAYS = 30
  BATCH_SIZE = 200

  def perform(window_days: WINDOW_DAYS, batch_size: BATCH_SIZE)
    cutoff = window_days.to_i.days.ago

    scope = Purchase.where(receipt_status: :pending)
      .where.not(stripe_payment_intent_id: [ nil, "" ])
      .where("created_at >= ?", cutoff)

    scope.in_batches(of: batch_size.to_i) do |relation|
      relation.each do |purchase|
        next unless purchase.receipt_status == "pending"
        next if purchase.stripe_payment_intent_id.blank?

        status, url, stripe_charge_id = Payments::StripeReceiptLookup.lookup(payment_intent_id: purchase.stripe_payment_intent_id)

        case status
        when :available
          purchase.update!(receipt_url: url, receipt_status: :available, stripe_charge_id: purchase.stripe_charge_id.presence || stripe_charge_id.presence)
        when :unavailable
          purchase.update!(receipt_status: :unavailable, stripe_charge_id: purchase.stripe_charge_id.presence || stripe_charge_id.presence)
        else
          purchase.update!(stripe_charge_id: purchase.stripe_charge_id.presence || stripe_charge_id.presence) if stripe_charge_id.present?
        end
      rescue => e
        AppLogger.error(event: "purchases.receipt_backfill.error", error: e, purchase_id: purchase&.id, stripe_payment_intent_id: purchase&.stripe_payment_intent_id)
        next
      end
    end
  end
end
