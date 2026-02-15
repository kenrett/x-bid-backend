require "digest"
require "securerandom"

class SessionToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, lambda {
    now = Time.current
    absolute_cutoff = now - absolute_ttl
    where(revoked_at: nil)
      .where("expires_at > ?", now)
      .where("created_at > ?", absolute_cutoff)
  }

  scope :inactive, lambda {
    now = Time.current
    absolute_cutoff = now - absolute_ttl
    where.not(revoked_at: nil)
      .or(where("expires_at <= ?", now))
      .or(where("created_at <= ?", absolute_cutoff))
  }

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.generate_for(user:, ttl: default_ttl, two_factor_verified_at: nil)
    raw_token = SecureRandom.hex(32)
    expires_at = Time.current + ttl
    session_token = user.session_tokens.create!(
      token_digest: digest(raw_token),
      expires_at: expires_at,
      two_factor_verified_at: two_factor_verified_at
    )
    [ session_token, raw_token ]
  end

  def self.find_active_by_raw_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token))&.tap do |session_token|
      return nil unless session_token.active?
    end
  end

  def self.default_ttl
    idle_ttl
  end

  def self.idle_ttl
    Rails.configuration.x.session_token_idle_ttl || Rails.configuration.x.session_token_ttl || 10.minutes
  end

  def self.absolute_ttl
    Rails.configuration.x.session_token_absolute_ttl || 2.hours
  end

  def absolute_expires_at
    return nil if created_at.blank?

    created_at + self.class.absolute_ttl
  end

  def sliding_expires_at(now: Time.current)
    idle_expires_at = now + self.class.idle_ttl
    absolute_deadline = absolute_expires_at
    return idle_expires_at if absolute_deadline.blank?

    [ idle_expires_at, absolute_deadline ].min
  end

  def active?(now: Time.current)
    return false unless revoked_at.nil?
    return false unless expires_at.present? && expires_at > now

    absolute_deadline = absolute_expires_at
    return false if absolute_deadline.present? && absolute_deadline <= now

    true
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
