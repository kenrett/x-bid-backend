class Notification < ApplicationRecord
  belongs_to :user

  enum :kind, {
    auction_won: "auction_won",
    purchase_completed: "purchase_completed",
    fulfillment_shipped: "fulfillment_shipped"
  }

  validates :kind, presence: true
  validates :data, presence: true
end
