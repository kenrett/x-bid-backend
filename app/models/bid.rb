class Bid < ApplicationRecord
  belongs_to :user
  belongs_to :auction

  include StorefrontKeyable

  validates :amount, numericality: { greater_than: ->(bid) { bid.auction.current_price }, message: "must be greater than the auction's current price" }
end
