class AddSkuToBidPacks < ActiveRecord::Migration[8.0]
  def change
    add_column :bid_packs, :sku, :string
    add_index :bid_packs, :sku, unique: true
  end
end
