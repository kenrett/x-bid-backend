class AddRefundFieldsToPurchases < ActiveRecord::Migration[8.0]
  def change
    add_column :purchases, :amount_cents, :integer, null: false, default: 0
    add_column :purchases, :currency, :string, null: false, default: "usd"
    add_column :purchases, :refunded_cents, :integer, null: false, default: 0
    add_column :purchases, :refund_reason, :string
    add_column :purchases, :refund_id, :string
    add_column :purchases, :refunded_at, :datetime
    add_column :purchases, :stripe_payment_intent_id, :string

    add_index :purchases, :stripe_payment_intent_id, unique: true
  end
end
