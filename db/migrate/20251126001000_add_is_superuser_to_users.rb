class AddIsSuperuserToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :is_superuser, :boolean, default: false, null: false
    add_index :users, :is_superuser
  end
end
