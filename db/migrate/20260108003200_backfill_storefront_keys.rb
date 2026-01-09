class BackfillStorefrontKeys < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CANONICAL_KEYS = %w[main afterdark artisan].freeze
  DEFAULT_KEY = "main"
  BATCH_SIZE = (ENV["STOREFRONT_BACKFILL_BATCH_SIZE"].presence || 50_000).to_i

  def up
    say_with_time "Backfilling auctions.storefront_key" do
      batched_update(
        table: "auctions",
        where_sql: "auctions.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
      )
    end

    say_with_time "Backfilling bids.storefront_key from auctions" do
      batched_update(
        table: "bids",
        from_sql: "FROM auctions",
        id_range_where_sql: "bids.storefront_key IS NULL AND bids.auction_id IS NOT NULL",
        where_sql: "bids.auction_id = auctions.id AND bids.storefront_key IS NULL",
        set_sql: "storefront_key = auctions.storefront_key"
      )
    end

    say_with_time "Backfilling auction_settlements.storefront_key from auctions" do
      batched_update(
        table: "auction_settlements",
        from_sql: "FROM auctions",
        id_range_where_sql: "auction_settlements.storefront_key IS NULL",
        where_sql: "auction_settlements.auction_id = auctions.id AND auction_settlements.storefront_key IS NULL",
        set_sql: "storefront_key = auctions.storefront_key"
      )
    end

    say_with_time "Backfilling purchases.storefront_key" do
      batched_update(
        table: "purchases",
        where_sql: "purchases.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
      )
    end

    say_with_time "Backfilling credit_transactions.storefront_key from purchase/auction" do
      batched_update(
        table: "credit_transactions",
        from_sql: "FROM purchases",
        id_range_where_sql: "credit_transactions.storefront_key IS NULL AND credit_transactions.purchase_id IS NOT NULL",
        where_sql: "credit_transactions.purchase_id = purchases.id AND credit_transactions.storefront_key IS NULL",
        set_sql: "storefront_key = purchases.storefront_key"
      )

      batched_update(
        table: "credit_transactions",
        from_sql: "FROM auctions",
        id_range_where_sql: "credit_transactions.storefront_key IS NULL AND credit_transactions.auction_id IS NOT NULL",
        where_sql: "credit_transactions.auction_id = auctions.id AND credit_transactions.storefront_key IS NULL",
        set_sql: "storefront_key = auctions.storefront_key"
      )

      batched_update(
        table: "credit_transactions",
        where_sql: "credit_transactions.storefront_key IS NULL",
        set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
      )
    end

    say_with_time "Backfilling money_events.storefront_key from source" do
      begin
        disable_money_events_mutation_triggers!

        batched_update(
          table: "money_events",
          from_sql: "FROM bids",
          id_range_where_sql: "money_events.storefront_key IS NULL AND money_events.source_type = 'Bid'",
          where_sql: "money_events.source_type = 'Bid' AND money_events.source_id = bids.id::text AND money_events.storefront_key IS NULL",
          set_sql: "storefront_key = bids.storefront_key"
        )

        batched_update(
          table: "money_events",
          from_sql: "FROM purchases",
          id_range_where_sql: "money_events.storefront_key IS NULL AND money_events.source_type = 'Purchase'",
          where_sql: "money_events.source_type = 'Purchase' AND money_events.source_id = purchases.id::text AND money_events.storefront_key IS NULL",
          set_sql: "storefront_key = purchases.storefront_key"
        )

        batched_update(
          table: "money_events",
          where_sql: "money_events.storefront_key IS NULL",
          set_sql: "storefront_key = #{connection.quote(DEFAULT_KEY)}"
        )
      ensure
        enable_money_events_mutation_triggers!
      end
    end

    log_counts!
  end

  def down
    # Intentionally no-op: we don't want to drop/erase attribution data.
  end

  private

  def log_counts!
    %w[auctions bids auction_settlements purchases credit_transactions money_events].each do |table|
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

  def disable_money_events_mutation_triggers!
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'money_events_prevent_update'
            AND tgrelid = 'money_events'::regclass
        ) THEN
          ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_update;
        END IF;

        IF EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'money_events_prevent_delete'
            AND tgrelid = 'money_events'::regclass
        ) THEN
          ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_delete;
        END IF;
      END;
      $$;
    SQL
  end

  def enable_money_events_mutation_triggers!
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'money_events_prevent_update'
            AND tgrelid = 'money_events'::regclass
        ) THEN
          ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_update;
        END IF;

        IF EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'money_events_prevent_delete'
            AND tgrelid = 'money_events'::regclass
        ) THEN
          ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_delete;
        END IF;
      END;
      $$;
    SQL
  rescue StandardError => e
    say "Warning: failed to re-enable money_events mutation triggers: #{e.class}: #{e.message}"
  end
end
