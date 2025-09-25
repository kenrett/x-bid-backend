class CreateBids < ActiveRecord::Migration[8.0]
  def change
    create_table :bids do |t|
      t.references :user, null: false, foreign_key: true
      t.references :auction, null: false, foreign_key: true
      t.decimal :amount, precision: 6, scale: 2
      t.boolean :auto

      t.timestamps
    end
  end
end
