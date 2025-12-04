require "test_helper"

class AuctionsEventsTest < ActiveSupport::TestCase
  def setup
    @auction = Auction.create!(title: "Auction", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @bid = Bid.create!(user: @user, auction: @auction, amount: 2.0)
  end

  test "broadcasts bid placed event" do
    assert_nothing_raised do
      Auctions::Events.bid_placed(auction: @auction, bid: @bid)
    end
  end
end
