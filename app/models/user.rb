class User < ApplicationRecord
  has_secure_password

  enum :role, { user: 0, admin: 1 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, :role, :password_digest, presence: true
end
