class AddWinningUserToAuctions < ActiveRecord::Migration[8.0]
  def change
    add_reference :auctions, :winning_user, null: true, foreign_key: { to_table: :users }
  end
end
