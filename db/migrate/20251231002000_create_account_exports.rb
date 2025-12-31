class CreateAccountExports < ActiveRecord::Migration[8.0]
  def change
    create_table :account_exports do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :requested_at, null: false
      t.datetime :ready_at
      t.string :download_url
      t.text :error_message
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :account_exports, [ :user_id, :requested_at ]
    add_index :account_exports, :status
  end
end
