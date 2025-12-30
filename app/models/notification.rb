class Notification < ApplicationRecord
  # Notification contract (current behavior).
  #
  # Endpoint: GET /api/v1/me/notifications (Api::V1::Me::NotificationsController#index)
  # Client mapping key: `kind` (distinct from the activity feed's `type`).
  #
  # Current `kind` enum values:
  # - "auction_won"          (created from AuctionSettlement after_create; see AuctionSettlement#enqueue_win_email)
  # - "purchase_completed"   (created on successful bid pack purchase apply; see Payments::ApplyBidPackPurchase)
  # - "fulfillment_shipped"  (enum exists, but this repo currently has no Notification.create!(kind: :fulfillment_shipped, ...) call sites)
  belongs_to :user

  enum :kind, {
    auction_won: "auction_won",
    purchase_completed: "purchase_completed",
    fulfillment_shipped: "fulfillment_shipped"
  }

  validates :kind, presence: true
  validates :data, presence: true
end
