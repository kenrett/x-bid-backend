namespace :purchases do
  namespace :receipts do
    desc "Backfill Stripe receipt_url/receipt_status for recent purchases"
    task backfill: :environment do
      PurchaseReceiptBackfillJob.perform_now
    end
  end
end
