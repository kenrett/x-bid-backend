class User < ApplicationRecord
  has_secure_password

  has_many :bids, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :auction_watches, dependent: :destroy
  has_many :won_auctions, class_name: "Auction", foreign_key: "winning_user_id"
  has_many :session_tokens, dependent: :destroy
  has_many :password_reset_tokens, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :account_exports, dependent: :destroy

  enum :role, { user: 0, admin: 1, superadmin: 2 }, default: :user
  enum :status, { active: 0, disabled: 1 }, default: :active

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, :role, :status, :password_digest, presence: true
  # `bid_credits` is a cached balance; write through the credit ledger (Credits::Apply/Debit)
  # and use Credits::RebuildBalance to recompute from the ledger when needed.
  validates :bid_credits, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  NOTIFICATION_PREFERENCE_DEFAULTS = {
    bidding_alerts: true,
    outbid_alerts: true,
    watched_auction_ending: true,
    receipts: true,
    product_updates: false,
    marketing_emails: false
  }.freeze

  def email_verified?
    email_verified_at.present?
  end

  def notification_preferences_with_defaults
    defaults = NOTIFICATION_PREFERENCE_DEFAULTS
    stored = notification_preferences.to_h
    defaults.merge(stored.symbolize_keys).transform_keys(&:to_s)
  end

  def disable_and_revoke_sessions!
    transaction do
      update!(status: :disabled, disabled_at: Time.current)

      session_tokens.active.find_each do |session_token|
        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "user_disabled")
      end
    end
  end

  def anonymize_account!
    anonymized_email = "deleted+#{id}-#{SecureRandom.hex(6)}@example.invalid"
    update!(
      name: "Deleted User",
      email_address: anonymized_email,
      unverified_email_address: nil,
      email_verified_at: nil,
      email_verification_token_digest: nil,
      email_verification_sent_at: nil,
      password_digest: BCrypt::Password.create(SecureRandom.hex(32))
    )
  end

  def disable_revoke_and_anonymize!
    transaction do
      disable_and_revoke_sessions!
      anonymize_account!
    end
  end
end
