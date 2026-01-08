class AddStorefrontKeyIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :auctions, :storefront_key, algorithm: :concurrently
    add_index :bids, :storefront_key, algorithm: :concurrently
    add_index :auction_settlements, :storefront_key, algorithm: :concurrently

    add_index :purchases, [ :storefront_key, :created_at ], algorithm: :concurrently
    add_index :credit_transactions, [ :storefront_key, :created_at ], algorithm: :concurrently
    add_index :money_events, [ :storefront_key, :occurred_at ], algorithm: :concurrently
  end
end
