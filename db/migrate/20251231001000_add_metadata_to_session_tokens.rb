class AddMetadataToSessionTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :session_tokens, :user_agent, :text
    add_column :session_tokens, :ip_address, :string
    add_column :session_tokens, :last_seen_at, :datetime

    add_index :session_tokens, :last_seen_at
  end
end
