class NormalizePurchaseStatuses < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CANONICAL_STATUSES = %w[
    created
    paid_pending_apply
    applied
    failed
    partially_refunded
    refunded
    voided
  ].freeze

  def up
    normalize_legacy_statuses!
    assert_no_unknown_statuses!

    add_check_constraint(
      :purchases,
      "status IS NOT NULL AND status IN (#{quoted_statuses})",
      name: "purchases_status_allowed",
      validate: false
    )
    validate_check_constraint :purchases, name: "purchases_status_allowed"
  end

  def down
    remove_check_constraint :purchases, name: "purchases_status_allowed"
  end

  private

  def normalize_legacy_statuses!
    say_with_time "Normalizing purchases.status=completed to applied" do
      execute <<~SQL.squish
        UPDATE purchases
        SET status = 'applied'
        WHERE status = 'completed'
      SQL
    end

    say_with_time "Normalizing blank purchases.status to created" do
      execute <<~SQL.squish
        UPDATE purchases
        SET status = 'created'
        WHERE status IS NULL OR BTRIM(status) = ''
      SQL
    end

    say_with_time "Normalizing purchases.status=pending to created" do
      execute <<~SQL.squish
        UPDATE purchases
        SET status = 'created'
        WHERE status = 'pending'
      SQL
    end
  end

  def assert_no_unknown_statuses!
    unknown_statuses = select_values(<<~SQL.squish)
      SELECT DISTINCT status
      FROM purchases
      WHERE status IS NOT NULL
        AND BTRIM(status) <> ''
        AND status NOT IN (#{quoted_statuses})
    SQL

    return if unknown_statuses.empty?

    raise "Unknown purchase statuses found: #{unknown_statuses.sort.join(', ')}"
  end

  def quoted_statuses
    CANONICAL_STATUSES.map { |status| connection.quote(status) }.join(", ")
  end
end
