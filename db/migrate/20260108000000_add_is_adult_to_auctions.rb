class AddIsAdultToAuctions < ActiveRecord::Migration[8.0]
  def change
    add_column :auctions, :is_adult, :boolean, null: false, default: false
    add_index :auctions, :is_adult
  end
end
