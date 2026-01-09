class AddStorefrontKeyToAuditLogsAndBidPacks < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :storefront_key, :string
    add_column :bid_packs, :storefront_key, :string
  end
end
