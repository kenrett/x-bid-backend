class AddFulfillmentToAuctionSettlements < ActiveRecord::Migration[8.0]
  def change
    add_column :auction_settlements, :fulfillment_status, :integer, null: false, default: 0
    add_column :auction_settlements, :fulfillment_address, :jsonb
    add_column :auction_settlements, :shipping_cost, :decimal, precision: 6, scale: 2, null: false, default: 0
    add_column :auction_settlements, :shipping_carrier, :string
    add_column :auction_settlements, :tracking_number, :string

    add_index :auction_settlements, :fulfillment_status
  end
end
