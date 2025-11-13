class CreatePurchases < ActiveRecord::Migration[8.0]
  def change
    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :bid_pack, null: false, foreign_key: true
      t.string :stripe_checkout_session_id
      t.string :status

      t.timestamps
    end
    add_index :purchases, :stripe_checkout_session_id, unique: true
  end
end
