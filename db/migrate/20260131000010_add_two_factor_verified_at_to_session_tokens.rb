class AddTwoFactorVerifiedAtToSessionTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :session_tokens, :two_factor_verified_at, :datetime
    add_index :session_tokens, :two_factor_verified_at
  end
end
