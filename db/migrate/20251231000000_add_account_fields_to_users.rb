class AddAccountFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_verified_at, :datetime
    add_column :users, :email_verification_token_digest, :string
    add_column :users, :email_verification_sent_at, :datetime
    add_column :users, :unverified_email_address, :string

    add_column :users, :notification_preferences, :jsonb, null: false, default: {
      bidding_alerts: true,
      outbid_alerts: true,
      watched_auction_ending: true,
      receipts: true,
      product_updates: false,
      marketing_emails: false
    }

    add_column :users, :disabled_at, :datetime

    add_index :users, :email_verification_token_digest
    add_index :users, :email_verified_at
    add_index :users, :unverified_email_address
  end
end
