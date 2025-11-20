require "digest"
require "securerandom"

class SessionToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.generate_for(user:, ttl: default_ttl)
    raw_token = SecureRandom.hex(32)
    expires_at = Time.current + ttl
    session_token = user.session_tokens.create!(token_digest: digest(raw_token), expires_at: expires_at)
    [session_token, raw_token]
  end

  def self.find_active_by_raw_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token))&.tap do |session_token|
      return nil unless session_token.active?
    end
  end

  def self.default_ttl
    Rails.configuration.x.session_token_ttl || 30.minutes
  end

  def active?
    revoked_at.nil? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
