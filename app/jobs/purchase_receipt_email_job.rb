class PurchaseReceiptEmailJob < ApplicationJob
  queue_as :default

  def perform(purchase_id, storefront_key: nil)
    with_storefront_context(storefront_key: storefront_key) do
      TransactionalMailer.purchase_receipt(purchase_id).deliver_now
    end
  end
end
