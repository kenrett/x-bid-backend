class CreateActivityEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :activity_events, [ :user_id, :occurred_at ]
    add_index :activity_events, :event_type
  end
end
