class AddReceiptUrlToPurchases < ActiveRecord::Migration[8.0]
  def change
    # Stripe-hosted receipt URL for the underlying successful charge.
    # Nullable because not all payment methods / flows produce a receipt URL.
    add_column :purchases, :receipt_url, :string
  end
end
