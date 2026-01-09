class AddStorefrontKeyConstraintsToAuditLogsAndBidPacks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CANONICAL = %w[main afterdark artisan].freeze

  def up
    add_and_validate_constraints(:audit_logs)
    add_and_validate_constraints(:bid_packs)
  end

  def down
    remove_check_constraint(:audit_logs, name: "audit_logs_storefront_key_allowed")
    remove_check_constraint(:audit_logs, name: "audit_logs_storefront_key_not_null")

    remove_check_constraint(:bid_packs, name: "bid_packs_storefront_key_allowed")
    remove_check_constraint(:bid_packs, name: "bid_packs_storefront_key_not_null")
  end

  private

  def add_and_validate_constraints(table)
    allowed_name = "#{table}_storefront_key_allowed"
    not_null_name = "#{table}_storefront_key_not_null"

    add_check_constraint(
      table,
      "storefront_key IN (#{CANONICAL.map { |k| connection.quote(k) }.join(", ")})",
      name: allowed_name,
      validate: false
    )
    add_check_constraint(
      table,
      "storefront_key IS NOT NULL",
      name: not_null_name,
      validate: false
    )

    validate_check_constraint(table, name: allowed_name)
    validate_check_constraint(table, name: not_null_name)
  end
end
