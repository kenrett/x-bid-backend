class AddStorefrontKeyToCoreTables < ActiveRecord::Migration[8.0]
  def change
    add_column :auctions, :storefront_key, :string
    add_column :bids, :storefront_key, :string
    add_column :purchases, :storefront_key, :string
    add_column :credit_transactions, :storefront_key, :string
    add_column :money_events, :storefront_key, :string
    add_column :auction_settlements, :storefront_key, :string
  end
end
