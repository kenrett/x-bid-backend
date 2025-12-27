class CreateAuctionWatches < ActiveRecord::Migration[8.0]
  def change
    create_table :auction_watches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :auction, null: false, foreign_key: true

      t.timestamps
    end

    add_index :auction_watches, [ :user_id, :auction_id ], unique: true
  end
end
