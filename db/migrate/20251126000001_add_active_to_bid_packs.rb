class AddActiveToBidPacks < ActiveRecord::Migration[8.0]
  def change
    add_column :bid_packs, :active, :boolean, default: true, null: false
    add_index :bid_packs, :active
  end
end
