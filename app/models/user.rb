class User < ApplicationRecord
  has_secure_password

  has_many :bids, dependent: :destroy
  has_many :purchases, dependent: :destroy
  has_many :won_auctions, class_name: "Auction", foreign_key: "winning_user_id"
  has_many :session_tokens, dependent: :destroy
  has_many :password_reset_tokens, dependent: :destroy

  enum :role, { user: 0, admin: 1, superadmin: 2 }, default: :user
  enum :status, { active: 0, disabled: 1 }, default: :active

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, :role, :status, :password_digest, presence: true
  validates :bid_credits, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def disable_and_revoke_sessions!
    transaction do
      update!(status: :disabled)

      session_tokens.active.find_each do |session_token|
        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "user_disabled")
      end
    end
  end
end
