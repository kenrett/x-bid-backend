class CreateAuctions < ActiveRecord::Migration[8.0]
  def change
    create_table :auctions do |t|
      t.string :title
      t.text :description
      t.datetime :start_date
      t.datetime :end_time
      t.decimal :current_price, precision: 6, scale: 2
      t.string :image_url
      t.integer :status, default: 0, null: false

      t.timestamps
    end
  end
end
