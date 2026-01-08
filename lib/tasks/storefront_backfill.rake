namespace :storefront do
  desc "Backfill storefront_key on core tables (safe to re-run)"
  task backfill_storefront_keys: :environment do
    default_key = "main"
    batch_size = (ENV["STOREFRONT_BACKFILL_BATCH_SIZE"].presence || 50_000).to_i

    connection = ActiveRecord::Base.connection

    batched_update = lambda do |table:, where_sql:, set_sql:, from_sql: nil, id_range_where_sql: nil|
      id_range_where_sql ||= where_sql

      min_id = connection.select_value("SELECT MIN(id) FROM #{table} WHERE #{id_range_where_sql}")
      max_id = connection.select_value("SELECT MAX(id) FROM #{table} WHERE #{id_range_where_sql}")

      next if min_id.blank? || max_id.blank?

      min_id = min_id.to_i
      max_id = max_id.to_i
      next if min_id <= 0 || max_id <= 0

      puts "storefront:backfill_storefront_keys #{table}: id range #{min_id}..#{max_id} (batch_size=#{batch_size})"

      min_id.step(max_id, batch_size) do |batch_start|
        batch_end = [ batch_start + batch_size - 1, max_id ].min
        connection.execute(<<~SQL.squish)
          UPDATE #{table}
          SET #{set_sql}
          #{from_sql}
          WHERE #{where_sql}
            AND #{table}.id BETWEEN #{batch_start} AND #{batch_end}
        SQL
      end
    end

    puts "storefront:backfill_storefront_keys starting (batch_size=#{batch_size})"

    batched_update.call(
      table: "auctions",
      where_sql: "auctions.storefront_key IS NULL",
      set_sql: "storefront_key = #{connection.quote(default_key)}"
    )

    batched_update.call(
      table: "bids",
      from_sql: "FROM auctions",
      id_range_where_sql: "bids.storefront_key IS NULL AND bids.auction_id IS NOT NULL",
      where_sql: "bids.auction_id = auctions.id AND bids.storefront_key IS NULL",
      set_sql: "storefront_key = auctions.storefront_key"
    )

    batched_update.call(
      table: "auction_settlements",
      from_sql: "FROM auctions",
      id_range_where_sql: "auction_settlements.storefront_key IS NULL",
      where_sql: "auction_settlements.auction_id = auctions.id AND auction_settlements.storefront_key IS NULL",
      set_sql: "storefront_key = auctions.storefront_key"
    )

    batched_update.call(
      table: "purchases",
      where_sql: "purchases.storefront_key IS NULL",
      set_sql: "storefront_key = #{connection.quote(default_key)}"
    )

    batched_update.call(
      table: "credit_transactions",
      from_sql: "FROM purchases",
      id_range_where_sql: "credit_transactions.storefront_key IS NULL AND credit_transactions.purchase_id IS NOT NULL",
      where_sql: "credit_transactions.purchase_id = purchases.id AND credit_transactions.storefront_key IS NULL",
      set_sql: "storefront_key = purchases.storefront_key"
    )

    batched_update.call(
      table: "credit_transactions",
      from_sql: "FROM auctions",
      id_range_where_sql: "credit_transactions.storefront_key IS NULL AND credit_transactions.auction_id IS NOT NULL",
      where_sql: "credit_transactions.auction_id = auctions.id AND credit_transactions.storefront_key IS NULL",
      set_sql: "storefront_key = auctions.storefront_key"
    )

    batched_update.call(
      table: "credit_transactions",
      where_sql: "credit_transactions.storefront_key IS NULL",
      set_sql: "storefront_key = #{connection.quote(default_key)}"
    )

    begin
      connection.execute("ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_update")
      connection.execute("ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_delete")

      batched_update.call(
        table: "money_events",
        from_sql: "FROM bids",
        id_range_where_sql: "money_events.storefront_key IS NULL AND money_events.source_type = 'Bid'",
        where_sql: "money_events.source_type = 'Bid' AND money_events.source_id = bids.id::text AND money_events.storefront_key IS NULL",
        set_sql: "storefront_key = bids.storefront_key"
      )

      batched_update.call(
        table: "money_events",
        from_sql: "FROM purchases",
        id_range_where_sql: "money_events.storefront_key IS NULL AND money_events.source_type = 'Purchase'",
        where_sql: "money_events.source_type = 'Purchase' AND money_events.source_id = purchases.id::text AND money_events.storefront_key IS NULL",
        set_sql: "storefront_key = purchases.storefront_key"
      )

      batched_update.call(
        table: "money_events",
        where_sql: "money_events.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(default_key)}"
      )
    ensure
      begin
        connection.execute("ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_update")
        connection.execute("ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_delete")
      rescue StandardError => e
        warn "storefront:backfill_storefront_keys warning: failed to re-enable money_events triggers: #{e.class}: #{e.message}"
      end
    end

    %w[auctions bids auction_settlements purchases credit_transactions money_events].each do |table|
      counts = connection.select_all(<<~SQL.squish).to_a
        SELECT storefront_key, COUNT(*)::bigint AS count
        FROM #{table}
        GROUP BY storefront_key
        ORDER BY storefront_key
      SQL
      puts "storefront:backfill_storefront_keys #{table} by storefront_key: #{counts.inspect}"
    end
  end
end
