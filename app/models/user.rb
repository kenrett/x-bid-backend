class User < ApplicationRecord
  has_secure_password

  has_many :bids, dependent: :destroy
  has_many :won_auctions, class_name: "Auction", foreign_key: "winning_user_id"

  enum :role, { user: 0, admin: 1 }, default: :user

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, :role, :password_digest, presence: true
  validates :bid_credits, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
