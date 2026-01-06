class AddIncidentResponseFieldsToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :request_id, :string
    add_column :audit_logs, :session_token_id, :bigint
    add_column :audit_logs, :user_id, :bigint

    add_index :audit_logs, :request_id
    add_index :audit_logs, :session_token_id
    add_index :audit_logs, :user_id

    change_column_null :audit_logs, :actor_id, true
  end
end
