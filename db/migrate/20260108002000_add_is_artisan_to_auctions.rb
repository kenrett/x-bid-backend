class AddIsArtisanToAuctions < ActiveRecord::Migration[8.0]
  def change
    add_column :auctions, :is_artisan, :boolean, null: false, default: false
    add_index :auctions, :is_artisan
  end
end
