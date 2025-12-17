require "test_helper"

class ExpireAuctionSettlementsJobTest < ActiveSupport::TestCase
  test "expires settlements past the retry window" do
    user = User.create!(name: "Winner", email_address: "expire@example.com", password: "password", bid_credits: 0)
    auction = Auction.create!(title: "Expired", description: "Desc", start_date: 2.days.ago, end_time: 1.day.ago, current_price: 5.0, status: :ended, winning_user: user)
    settlement = AuctionSettlement.create!(
      auction: auction,
      winning_user: user,
      final_price: 5.0,
      currency: "usd",
      status: :payment_failed,
      ended_at: 2.days.ago
    )

    ExpireAuctionSettlementsJob.perform_now(Time.current)

    assert_equal "cancelled", settlement.reload.status
    assert_equal "payment_window_expired", settlement.failure_reason
  end

  test "does not expire settlements within the retry window" do
    user = User.create!(name: "Winner", email_address: "active@example.com", password: "password", bid_credits: 0)
    auction = Auction.create!(title: "Active", description: "Desc", start_date: 1.hour.ago, end_time: 30.minutes.ago, current_price: 5.0, status: :ended, winning_user: user)
    settlement = AuctionSettlement.create!(
      auction: auction,
      winning_user: user,
      final_price: 5.0,
      currency: "usd",
      status: :pending_payment,
      ended_at: 1.hour.ago
    )

    ExpireAuctionSettlementsJob.perform_now(Time.current)

    assert_equal "pending_payment", settlement.reload.status
  end
end
