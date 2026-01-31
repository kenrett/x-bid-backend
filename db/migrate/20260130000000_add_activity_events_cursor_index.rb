class AddActivityEventsCursorIndex < ActiveRecord::Migration[8.0]
  def change
    add_index :activity_events, [ :user_id, :occurred_at, :id ]
  end
end
