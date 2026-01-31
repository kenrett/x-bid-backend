class UpdateStorefrontKeyConstraintsForMarketplace < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  NEW_KEYS = %w[main afterdark marketplace].freeze
  OLD_KEYS = %w[main afterdark artisan].freeze
  TABLES = %i[
    auctions
    bids
    purchases
    credit_transactions
    money_events
    auction_settlements
    audit_logs
    bid_packs
  ].freeze

  def up
    migrate_storefront_values!("artisan", "marketplace")
    TABLES.each { |table| replace_allowed_constraint(table, NEW_KEYS) }
  end

  def down
    migrate_storefront_values!("marketplace", "artisan")
    TABLES.each { |table| replace_allowed_constraint(table, OLD_KEYS) }
  end

  private

  def replace_allowed_constraint(table, keys)
    name = "#{table}_storefront_key_allowed"
    remove_check_constraint(table, name: name, if_exists: true)
    add_check_constraint(
      table,
      "storefront_key IN (#{keys.map { |k| connection.quote(k) }.join(", ")})",
      name: name,
      validate: false
    )
    validate_check_constraint(table, name: name)
  end

  def migrate_storefront_values!(from_key, to_key)
    TABLES.each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET storefront_key = #{connection.quote(to_key)}
        WHERE storefront_key = #{connection.quote(from_key)}
      SQL
    end
  end
end
