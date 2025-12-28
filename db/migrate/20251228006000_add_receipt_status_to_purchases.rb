class AddReceiptStatusToPurchases < ActiveRecord::Migration[8.0]
  def change
    add_column :purchases, :receipt_status, :integer, null: false, default: 0
    add_index :purchases, :receipt_status

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE purchases
          SET receipt_status = 1
          WHERE receipt_url IS NOT NULL AND receipt_url <> ''
        SQL
      end
    end
  end
end
