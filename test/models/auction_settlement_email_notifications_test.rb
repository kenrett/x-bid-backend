require "test_helper"

class AuctionSettlementEmailNotificationsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "mail job enqueued on auction win settlement create" do
    user = User.create!(name: "Winner", email_address: "winner_notify@example.com", password: "password", bid_credits: 0)
    auction = Auction.create!(title: "Won", description: "Desc", start_date: 2.days.ago, end_time: 1.day.ago, current_price: 5.0, status: :ended, winning_user: user)

    settlement = nil
    assert_enqueued_jobs 1, only: AuctionWinEmailJob do
      settlement = AuctionSettlement.create!(
        auction: auction,
        winning_user: user,
        final_price: 5.0,
        currency: "usd",
        status: :pending_payment,
        ended_at: 1.day.ago
      )
    end

    assert settlement.present?
    assert_enqueued_with(
      job: AuctionWinEmailJob,
      args: [ settlement.id, { storefront_key: settlement.storefront_key } ]
    )

    notification = Notification.find_by(user: user, kind: "auction_won")
    assert notification.present?
    assert_equal settlement.id, notification.data["settlement_id"]
    assert_equal auction.id, notification.data["auction_id"]
    assert_equal auction.title, notification.data["auction_title"]
  end

  test "no mail job enqueued for settlement without winner" do
    auction = Auction.create!(title: "No Winner", description: "Desc", start_date: 2.days.ago, end_time: 1.day.ago, current_price: 5.0, status: :ended)

    assert_no_enqueued_jobs only: AuctionWinEmailJob do
      AuctionSettlement.create!(
        auction: auction,
        winning_user: nil,
        final_price: 0.0,
        currency: "usd",
        status: :no_winner,
        ended_at: 1.day.ago
      )
    end
  end
end
