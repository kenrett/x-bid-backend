class AddNonNegativeChecks < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :users, "bid_credits >= 0", name: "users_bid_credits_non_negative"
    add_check_constraint :auctions, "current_price >= 0", name: "auctions_current_price_non_negative"
    add_check_constraint :bids, "amount >= 0", name: "bids_amount_non_negative"
    add_check_constraint :purchases, "amount_cents >= 0", name: "purchases_amount_cents_non_negative"
    add_check_constraint :purchases, "refunded_cents >= 0", name: "purchases_refunded_cents_non_negative"
  end
end
