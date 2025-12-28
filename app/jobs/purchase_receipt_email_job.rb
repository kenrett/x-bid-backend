class PurchaseReceiptEmailJob < ApplicationJob
  queue_as :default

  def perform(purchase_id)
    TransactionalMailer.purchase_receipt(purchase_id).deliver_now
  end
end
