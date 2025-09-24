class CreateBidPacks < ActiveRecord::Migration[8.0]
  def change
    create_table :bid_packs do |t|
      t.string :name
      t.integer :bids
      t.decimal :price, precision: 6, scale: 2
      t.boolean :highlight
      t.text :description

      t.timestamps
    end
  end
end
