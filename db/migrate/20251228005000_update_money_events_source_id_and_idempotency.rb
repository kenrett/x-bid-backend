class UpdateMoneyEventsSourceIdAndIdempotency < ActiveRecord::Migration[8.0]
  def up
    # This migration may run after older code wrote Stripe payment intent IDs into a bigint `source_id`,
    # which PostgreSQL type-cast to 0. We normalize those rows before adding a uniqueness constraint.
    execute "ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_update"
    execute "ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_delete"

    change_column :money_events, :source_id, :string, using: "source_id::text"

    # Backfill `source_id` from the referenced purchase when possible.
    execute <<~SQL
      UPDATE money_events
      SET source_id = purchases.stripe_payment_intent_id
      FROM purchases
      WHERE money_events.source_type = 'StripePaymentIntent'
        AND money_events.event_type = 'purchase'
        AND (money_events.source_id IS NULL OR money_events.source_id = '0')
        AND (money_events.metadata->>'purchase_id') IS NOT NULL
        AND purchases.id = (money_events.metadata->>'purchase_id')::bigint
        AND purchases.stripe_payment_intent_id IS NOT NULL
    SQL

    # Any remaining StripePaymentIntent purchase rows without a valid source_id can't participate in idempotency.
    # Nulling these avoids blocking the unique index while keeping historical rows.
    execute <<~SQL
      UPDATE money_events
      SET source_type = NULL, source_id = NULL
      WHERE source_type = 'StripePaymentIntent'
        AND event_type = 'purchase'
        AND (source_id IS NULL OR source_id = '0')
    SQL

    # De-duplicate any remaining collisions by nulling the source reference on all but one row.
    execute <<~SQL
      WITH ranked AS (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY source_type, source_id, event_type
            ORDER BY occurred_at ASC, id ASC
          ) AS rn
        FROM money_events
        WHERE source_type IS NOT NULL
          AND source_id IS NOT NULL
          AND event_type IS NOT NULL
      )
      UPDATE money_events
      SET source_type = NULL, source_id = NULL
      WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    SQL

    add_index(
      :money_events,
      [ :source_type, :source_id, :event_type ],
      unique: true,
      name: "uniq_money_events_source_type_source_id_event_type"
    )

    execute "ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_update"
    execute "ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_delete"
  end

  def down
    execute "ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_update"
    execute "ALTER TABLE money_events DISABLE TRIGGER money_events_prevent_delete"

    remove_index :money_events, name: "uniq_money_events_source_type_source_id_event_type"
    change_column :money_events, :source_id, :bigint, using: "source_id::bigint"

    execute "ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_update"
    execute "ALTER TABLE money_events ENABLE TRIGGER money_events_prevent_delete"
  end
end
