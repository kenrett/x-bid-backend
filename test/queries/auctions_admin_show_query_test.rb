require "test_helper"

class AuctionsAdminShowQueryTest < ActiveSupport::TestCase
  def setup
    @winner = User.create!(name: "Winner", email_address: "winner@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Admin View Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 5.0,
      status: :active,
      winning_user: @winner
    )
    @bid = Bid.create!(user: @winner, auction: @auction, amount: 6.0)
  end

  test "fetches auction with bids and winning user eagerly loaded" do
    result = Auctions::Queries::AdminShow.call(params: { id: @auction.id })

    record = result.record
    assert_equal @auction.id, record.id
    assert record.association(:bids).loaded?
    assert record.association(:winning_user).loaded?
    assert_equal @bid.id, record.bids.first.id
  end

  test "raises when not found" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Auctions::Queries::AdminShow.call(params: { id: -1 })
    end
  end
end
