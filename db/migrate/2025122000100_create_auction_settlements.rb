class CreateAuctionSettlements < ActiveRecord::Migration[8.0]
  def change
    create_table :auction_settlements do |t|
      t.references :auction, null: false, foreign_key: true, index: { unique: true }
      t.references :winning_user, foreign_key: { to_table: :users }
      t.references :winning_bid, foreign_key: { to_table: :bids }
      t.decimal :final_price, precision: 6, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "usd"
      t.integer :status, null: false, default: 0
      t.datetime :ended_at, null: false
      t.string :payment_intent_id
      t.datetime :paid_at
      t.datetime :failed_at
      t.string :failure_reason

      t.timestamps
    end

    add_index :auction_settlements, :payment_intent_id, unique: true
    add_index :auction_settlements, :status
  end
end
