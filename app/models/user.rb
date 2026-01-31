require "digest"
require "rotp"

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

  def two_factor_enabled?
    two_factor_enabled_at.present?
  end

  def two_factor_secret
    return nil if two_factor_secret_ciphertext.blank?

    two_factor_encryptor.decrypt_and_verify(two_factor_secret_ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def two_factor_secret=(secret)
    if secret.present?
      self.two_factor_secret_ciphertext = two_factor_encryptor.encrypt_and_sign(secret)
    else
      self.two_factor_secret_ciphertext = nil
    end
  end

  def generate_two_factor_recovery_codes!
    codes = Array.new(10) { SecureRandom.hex(4) }
    update!(two_factor_recovery_codes: codes.map { |code| digest_recovery_code(code) })
    codes
  end

  def consume_recovery_code!(code)
    digest = digest_recovery_code(code)
    return false unless two_factor_recovery_codes.include?(digest)

    update!(two_factor_recovery_codes: two_factor_recovery_codes - [ digest ])
    true
  end

  def clear_two_factor!
    update!(
      two_factor_secret_ciphertext: nil,
      two_factor_enabled_at: nil,
      two_factor_recovery_codes: []
    )
  end

  def verify_two_factor_code(code)
    return false if code.to_s.strip.blank?

    secret = two_factor_secret
    return false if secret.blank?

    totp = ROTP::TOTP.new(secret, issuer: two_factor_issuer)
    totp.verify(code.to_s, drift_behind: 30, drift_ahead: 30).present?
  end

  def two_factor_provisioning_uri
    secret = two_factor_secret
    return nil if secret.blank?

    label = "#{two_factor_issuer}:#{email_address}"
    ROTP::TOTP.new(secret, issuer: two_factor_issuer).provisioning_uri(label)
  end

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

  private

  def two_factor_encryptor
    secret = Rails.application.secret_key_base
    salt = "two-factor-secret"
    key = ActiveSupport::KeyGenerator.new(secret).generate_key(salt, 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end

  def two_factor_issuer
    ENV.fetch("APP_NAME", "X-Bid")
  end

  def digest_recovery_code(code)
    Digest::SHA256.hexdigest(code.to_s)
  end
end
