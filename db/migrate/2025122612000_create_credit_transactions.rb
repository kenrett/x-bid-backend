class CreateCreditTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :amount, null: false
      t.string :reason, null: false
      t.string :idempotency_key, null: false
      t.references :purchase, foreign_key: true
      t.references :auction, foreign_key: true
      t.references :admin_actor, foreign_key: { to_table: :users }
      t.references :stripe_event, foreign_key: true
      t.string :stripe_payment_intent_id
      t.string :stripe_checkout_session_id
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :credit_transactions, [ :user_id, :created_at ], name: "index_credit_transactions_on_user_id_created_at"
    add_index :credit_transactions, :idempotency_key, unique: true, name: "unique_index_credit_transactions_on_idempotency_key"
    add_index :credit_transactions, :stripe_payment_intent_id
    add_index :credit_transactions, :stripe_checkout_session_id
  end
end
