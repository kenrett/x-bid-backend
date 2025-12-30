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

  test "status transitions emit activity events and shipped creates a notification" do
    fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @winner)

    assert_equal 0, ActivityEvent.count
    assert_equal 0, Notification.where(user: @winner, kind: :fulfillment_shipped).count

    fulfillment.transition_to!(:claimed, occurred_at: 3.days.ago)
    event = ActivityEvent.order(:id).last
    assert_equal @winner.id, event.user_id
    assert_equal "fulfillment_status_changed", event.event_type
    assert_equal "pending", event.data["from_status"]
    assert_equal "claimed", event.data["to_status"]
    assert_equal @settlement.id, event.data["settlement_id"]
    assert_equal fulfillment.id, event.data["fulfillment_id"]
    assert_equal @auction.id, event.data["auction_id"]

    fulfillment.transition_to!(:processing, occurred_at: 2.days.ago)
    fulfillment.update!(shipping_carrier: "UPS", tracking_number: "1Z999")
    fulfillment.transition_to!(:shipped, occurred_at: 1.day.ago)

    assert_equal 3, ActivityEvent.where(user: @winner, event_type: "fulfillment_status_changed").count

    notification = Notification.find_by(user: @winner, kind: :fulfillment_shipped)
    assert notification.present?
    assert_equal fulfillment.id, notification.data["fulfillment_id"]
    assert_equal @settlement.id, notification.data["settlement_id"]
    assert_equal @auction.id, notification.data["auction_id"]
    assert_equal "UPS", notification.data["shipping_carrier"]
    assert_equal "1Z999", notification.data["tracking_number"]
  end
end
