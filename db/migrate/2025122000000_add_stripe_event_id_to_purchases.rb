class AddStripeEventIdToPurchases < ActiveRecord::Migration[8.0]
  def change
    add_column :purchases, :stripe_event_id, :string
    add_index :purchases, :stripe_event_id, unique: true
  end
end
