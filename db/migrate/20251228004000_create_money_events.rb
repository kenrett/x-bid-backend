class CreateMoneyEvents < ActiveRecord::Migration[8.0]
  EVENT_TYPES = %w[purchase bid_spent refund admin_adjustment].freeze

  def change
    create_table :money_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :event_type, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.string :source_type
      t.bigint :source_id
      t.jsonb :metadata
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :money_events, [ :user_id, :occurred_at ], name: "index_money_events_on_user_id_occurred_at"
    add_index :money_events, [ :source_type, :source_id ], name: "index_money_events_on_source"
    add_index :money_events, :event_type

    add_check_constraint(
      :money_events,
      "event_type IN (#{EVENT_TYPES.map { |t| "'#{t}'" }.join(", ")})",
      name: "money_events_event_type_check"
    )
    add_check_constraint(
      :money_events,
      "char_length(currency) > 0",
      name: "money_events_currency_non_empty"
    )

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION prevent_money_events_mutation()
          RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'money_events are append-only';
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER money_events_prevent_update
          BEFORE UPDATE ON money_events
          FOR EACH ROW EXECUTE FUNCTION prevent_money_events_mutation();

          CREATE TRIGGER money_events_prevent_delete
          BEFORE DELETE ON money_events
          FOR EACH ROW EXECUTE FUNCTION prevent_money_events_mutation();
        SQL
      end

      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS money_events_prevent_update ON money_events;
          DROP TRIGGER IF EXISTS money_events_prevent_delete ON money_events;
          DROP FUNCTION IF EXISTS prevent_money_events_mutation();
        SQL
      end
    end
  end
end
