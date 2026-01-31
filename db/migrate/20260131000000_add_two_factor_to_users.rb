class AddTwoFactorToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :two_factor_secret_ciphertext, :text
    add_column :users, :two_factor_enabled_at, :datetime
    add_column :users, :two_factor_recovery_codes, :jsonb, default: [], null: false
  end
end
