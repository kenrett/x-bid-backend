require "digest"
require "securerandom"

class PasswordResetToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.generate_for(user:, ttl: default_ttl)
    raw_token = SecureRandom.hex(32)
    expires_at = Time.current + ttl
    token = user.password_reset_tokens.create!(token_digest: digest(raw_token), expires_at: expires_at)
    [ token, raw_token ]
  end

  def self.find_valid_by_raw_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token))&.tap do |token|
      return nil unless token.active?
    end
  end

  def self.default_ttl
    30.minutes
  end

  def active?
    used_at.nil? && expires_at.future?
  end

  def mark_used!
    update!(used_at: Time.current)
  end
end
