class AddRequestContextToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :ip_address, :string
    add_column :audit_logs, :user_agent, :text
    add_index :audit_logs, :created_at
  end
end
