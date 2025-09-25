class AddBidCreditsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :bid_credits, :integer, null: false, default: 0
  end
end
