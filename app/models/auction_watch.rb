class AuctionWatch < ApplicationRecord
  belongs_to :user
  belongs_to :auction

  validates :user_id, uniqueness: { scope: :auction_id }
end
