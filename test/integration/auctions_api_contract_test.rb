require "test_helper"

class AuctionsApiContractTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Contract Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 0.0,
      status: :active
    )
    @bidder = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    @bid = Bid.create!(user: @bidder, auction: @auction, amount: 1.0, created_at: 30.minutes.ago)
  end

  test "GET /api/v1/auctions/:id returns auction payload" do
    get "/api/v1/auctions/#{@auction.id}"

    assert_response :success
    body = JSON.parse(response.body)
    auction_json = body["auction"] || body
    assert_equal @auction.id, auction_json["id"]
    assert_equal @auction.title, auction_json["title"]
    assert_equal @auction.description, auction_json["description"]
    assert_equal @auction.current_price.to_s, auction_json["current_price"].to_s
  end

  test "GET /api/v1/auctions returns only active auctions" do
    pending = Auction.create!(
      title: "Pending Auction",
      description: "Desc",
      start_date: 2.days.from_now,
      end_time: 3.days.from_now,
      current_price: 0.0,
      status: :pending
    )
    ended = Auction.create!(
      title: "Ended Auction",
      description: "Desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: 0.0,
      status: :ended
    )
    inactive = Auction.create!(
      title: "Inactive Auction",
      description: "Desc",
      start_date: 4.days.ago,
      end_time: 3.days.ago,
      current_price: 0.0,
      status: :inactive
    )
    cancelled = Auction.create!(
      title: "Cancelled Auction",
      description: "Desc",
      start_date: 5.days.ago,
      end_time: 4.days.ago,
      current_price: 0.0,
      status: :cancelled
    )

    get "/api/v1/auctions"

    assert_response :success
    auctions = JSON.parse(response.body)
    assert_kind_of Array, auctions
    ids = auctions.map { |auction| auction.fetch("id") }
    statuses = auctions.map { |auction| auction.fetch("status") }.uniq

    assert_includes ids, @auction.id
    refute_includes ids, pending.id
    refute_includes ids, ended.id
    refute_includes ids, inactive.id
    refute_includes ids, cancelled.id
    assert_equal [ "active" ], statuses
  end

  test "GET /api/v1/auctions/:auction_id/bid_history returns bids" do
    older_bid = Bid.create!(user: @bidder, auction: @auction, amount: 2.5, created_at: 10.minutes.ago)
    newer_bid = Bid.create!(user: @bidder, auction: @auction, amount: 3.0, created_at: 1.minute.ago)

    get "/api/v1/auctions/#{@auction.id}/bid_history"

    assert_response :success
    body = JSON.parse(response.body)
    bids = body["bids"]
    assert_kind_of Array, bids
    first = bids.first
    assert_equal newer_bid.id, first["id"]
    assert_equal @bidder.name, first["username"]
    assert_equal newer_bid.amount.to_s, first["amount"].to_s
  end
end
