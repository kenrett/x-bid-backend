class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.string :action, null: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :target_type
      t.bigint :target_id
      t.jsonb :payload, default: {}

      t.timestamps
    end

    add_index :audit_logs, [:target_type, :target_id]
    add_index :audit_logs, :action
  end
end
