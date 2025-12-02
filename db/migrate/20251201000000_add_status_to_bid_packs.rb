class AddStatusToBidPacks < ActiveRecord::Migration[8.0]
  def up
    add_column :bid_packs, :status, :integer, default: 0, null: false
    add_index :bid_packs, :status

    execute <<-SQL.squish
      UPDATE bid_packs
      SET status = CASE WHEN active = false THEN 1 ELSE 0 END
    SQL
  end

  def down
    remove_index :bid_packs, :status
    remove_column :bid_packs, :status
  end
end
