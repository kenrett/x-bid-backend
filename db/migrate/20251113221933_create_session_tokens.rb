class CreateSessionTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :session_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :session_tokens, :token_digest, unique: true
    add_index :session_tokens, :expires_at
  end
end
