require "test_helper"

class AuctionsApiContractTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Contract Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active
    )
    @bidder = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    @bid = Bid.create!(user: @bidder, auction: @auction, amount: 2.0)
  end

  test "GET /api/v1/auctions/:id returns auction payload" do
    get "/api/v1/auctions/#{@auction.id}"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @auction.id, body["id"]
    assert_equal @auction.title, body["title"]
    assert_equal @auction.description, body["description"]
    assert_equal @auction.current_price.to_s, body["current_price"].to_s
  end

  test "GET /api/v1/auctions/:auction_id/bid_history returns bids" do
    get "/api/v1/auctions/#{@auction.id}/bid_history"

    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    first = body.first
    assert_equal @bid.id, first["id"]
    assert_equal @bidder.name, first["username"]
    assert_equal @bid.amount.to_s, first["amount"].to_s
  end
end
