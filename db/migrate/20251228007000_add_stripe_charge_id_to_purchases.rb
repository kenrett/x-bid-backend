class AddStripeChargeIdToPurchases < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:purchases, :stripe_charge_id)
      add_column :purchases, :stripe_charge_id, :string
    end

    unless index_exists?(:purchases, :stripe_charge_id)
      add_index :purchases, :stripe_charge_id
    end
  end
end
