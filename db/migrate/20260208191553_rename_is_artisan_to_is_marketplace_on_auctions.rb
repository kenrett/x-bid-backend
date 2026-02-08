class RenameIsArtisanToIsMarketplaceOnAuctions < ActiveRecord::Migration[8.0]
  def change
    rename_column :auctions, :is_artisan, :is_marketplace
  end
end
