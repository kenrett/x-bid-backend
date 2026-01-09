class BackfillStorefrontKeysForAuditLogsAndBidPacks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  DEFAULT_KEY = "main"
  BATCH_SIZE = (ENV["STOREFRONT_BACKFILL_BATCH_SIZE"].presence || 50_000).to_i

  def up
    say_with_time "Backfilling bid_packs.storefront_key" do
      batched_update(
        table: "bid_packs",
        where_sql: "bid_packs.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
      )
    end

    say_with_time "Backfilling audit_logs.storefront_key from targets when possible" do
      %w[Auction Bid Purchase CreditTransaction MoneyEvent AuctionSettlement BidPack].each do |target_type|
        table = target_type.underscore.pluralize

        batched_update(
          table: "audit_logs",
          from_sql: "FROM #{table}",
          id_range_where_sql: "audit_logs.storefront_key IS NULL AND audit_logs.target_type = #{connection.quote(target_type)} AND audit_logs.target_id IS NOT NULL",
          where_sql: "audit_logs.target_type = #{connection.quote(target_type)} AND audit_logs.target_id = #{table}.id AND audit_logs.storefront_key IS NULL",
          set_sql: "storefront_key = #{table}.storefront_key"
        )
      rescue StandardError => e
        say "Warning: audit_logs backfill for #{target_type} failed: #{e.class}: #{e.message}"
      end

      batched_update(
        table: "audit_logs",
        where_sql: "audit_logs.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
      )
    end

    log_counts!
  end

  def down
    # Intentionally no-op: we don't want to drop/erase attribution data.
  end

  private

  def log_counts!
    %w[audit_logs bid_packs].each do |table|
      counts = select_all(<<~SQL.squish).to_a
        SELECT storefront_key, COUNT(*)::bigint AS count
        FROM #{table}
        GROUP BY storefront_key
        ORDER BY storefront_key
      SQL
      say "Backfill #{table} by storefront_key: #{counts.inspect}"
    end
  rescue StandardError => e
    say "Backfill storefront_key counts failed: #{e.class}: #{e.message}"
  end

  def batched_update(table:, where_sql:, set_sql:, from_sql: nil, id_range_where_sql: nil)
    id_range_where_sql ||= where_sql

    min_id = select_value(<<~SQL.squish)
      SELECT MIN(id) FROM #{table} WHERE #{id_range_where_sql}
    SQL
    max_id = select_value(<<~SQL.squish)
      SELECT MAX(id) FROM #{table} WHERE #{id_range_where_sql}
    SQL

    return if min_id.blank? || max_id.blank?

    min_id = min_id.to_i
    max_id = max_id.to_i
    return if min_id <= 0 || max_id <= 0

    say "Backfill #{table}: id range #{min_id}..#{max_id} (batch_size=#{BATCH_SIZE})"

    min_id.step(max_id, BATCH_SIZE) do |batch_start|
      batch_end = [ batch_start + BATCH_SIZE - 1, max_id ].min
      execute <<~SQL.squish
        UPDATE #{table}
        SET #{set_sql}
        #{from_sql}
        WHERE #{where_sql}
          AND #{table}.id BETWEEN #{batch_start} AND #{batch_end}
      SQL
    end
  end
end
