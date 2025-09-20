class CreateAuctions < ActiveRecord::Migration[8.0]
  def change
    create_table :auctions do |t|
      t.string :title
      t.text :description
      t.datetime :start_date
      t.decimal :current_price, precision: 6, scale: 2
      t.string :image_url
      t.string :status

      t.timestamps
    end
  end
end
