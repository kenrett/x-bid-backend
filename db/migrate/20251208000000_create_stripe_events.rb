class CreateStripeEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type
      t.jsonb :payload, default: {}
      t.datetime :processed_at

      t.timestamps
    end

    add_index :stripe_events, :stripe_event_id, unique: true
  end
end
