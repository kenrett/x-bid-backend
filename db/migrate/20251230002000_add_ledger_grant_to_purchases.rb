class AddLedgerGrantToPurchases < ActiveRecord::Migration[8.0]
  def change
    add_reference :purchases,
                  :ledger_grant_credit_transaction,
                  foreign_key: { to_table: :credit_transactions },
                  index: true
  end
end
