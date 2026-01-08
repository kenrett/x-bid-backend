class AddStorefrontKeyConstraints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CANONICAL = %w[main afterdark artisan].freeze

  def up
    add_and_validate_constraints(:auctions)
    add_and_validate_constraints(:bids)
    add_and_validate_constraints(:purchases)
    add_and_validate_constraints(:credit_transactions)
    add_and_validate_constraints(:money_events)
    add_and_validate_constraints(:auction_settlements)
  end

  def down
    remove_check_constraint(:auctions, name: "auctions_storefront_key_allowed")
    remove_check_constraint(:auctions, name: "auctions_storefront_key_not_null")

    remove_check_constraint(:bids, name: "bids_storefront_key_allowed")
    remove_check_constraint(:bids, name: "bids_storefront_key_not_null")

    remove_check_constraint(:purchases, name: "purchases_storefront_key_allowed")
    remove_check_constraint(:purchases, name: "purchases_storefront_key_not_null")

    remove_check_constraint(:credit_transactions, name: "credit_transactions_storefront_key_allowed")
    remove_check_constraint(:credit_transactions, name: "credit_transactions_storefront_key_not_null")

    remove_check_constraint(:money_events, name: "money_events_storefront_key_allowed")
    remove_check_constraint(:money_events, name: "money_events_storefront_key_not_null")

    remove_check_constraint(:auction_settlements, name: "auction_settlements_storefront_key_allowed")
    remove_check_constraint(:auction_settlements, name: "auction_settlements_storefront_key_not_null")
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
