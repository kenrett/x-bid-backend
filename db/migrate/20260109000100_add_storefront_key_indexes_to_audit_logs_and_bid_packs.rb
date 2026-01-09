class AddStorefrontKeyIndexesToAuditLogsAndBidPacks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :audit_logs, [ :storefront_key, :created_at ], algorithm: :concurrently
    add_index :bid_packs, :storefront_key, algorithm: :concurrently
  end
end
