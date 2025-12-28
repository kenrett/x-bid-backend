require "test_helper"

class AuctionFulfillmentTest < ActiveSupport::TestCase
  setup do
    @winner = User.create!(name: "Winner", email_address: "winner_fulfillment@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other_fulfillment@example.com", password: "password", bid_credits: 0)

    @auction = Auction.create!(
      title: "Prize",
      description: "Desc",
      start_date: 2.days.ago,
      end_time: 1.day.ago,
      current_price: 9.0,
      status: :ended,
      winning_user: @winner
    )
    @bid = Bid.create!(auction: @auction, user: @winner, amount: 10.0)
    @settlement = AuctionSettlement.create!(
      auction: @auction,
      winning_user: @winner,
      winning_bid: @bid,
      final_price: 10.0,
      currency: "usd",
      status: :paid,
      ended_at: 1.day.ago
    )
  end

  test "default status is pending" do
    fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @winner)
    assert_equal "pending", fulfillment.status
  end

  test "invalid transitions are rejected" do
    fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @winner)

    assert_raises(ActiveRecord::RecordInvalid) { fulfillment.update!(status: :processing) }
    assert_equal "pending", fulfillment.reload.status
  end

  test "valid transitions succeed" do
    fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @winner)

    fulfillment.transition_to!(:claimed)
    assert_equal "claimed", fulfillment.reload.status

    fulfillment.transition_to!(:processing)
    assert_equal "processing", fulfillment.reload.status

    fulfillment.transition_to!(:shipped)
    assert_equal "shipped", fulfillment.reload.status

    fulfillment.transition_to!(:complete)
    assert_equal "complete", fulfillment.reload.status
  end
end
