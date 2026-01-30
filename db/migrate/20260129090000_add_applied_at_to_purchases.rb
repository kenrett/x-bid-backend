class AddAppliedAtToPurchases < ActiveRecord::Migration[7.1]
  def change
    add_column :purchases, :applied_at, :datetime
    add_index :purchases, :applied_at
  end
end
