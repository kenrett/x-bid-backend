class CreateAuctionFulfillments < ActiveRecord::Migration[8.0]
  def change
    create_table :auction_fulfillments do |t|
      t.references :auction_settlement, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.jsonb :shipping_address
      t.integer :shipping_cost_cents
      t.string :shipping_carrier
      t.string :tracking_number
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auction_fulfillments, :status
  end
end
