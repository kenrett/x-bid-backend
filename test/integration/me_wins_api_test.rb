require "test_helper"
require "jwt"

class MeWinsApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(
      user: @other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    @won_auction_old = Auction.create!(
      title: "Old Win",
      description: "desc",
      start_date: 5.days.ago,
      end_time: 3.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: @user
    )
    @won_bid_old = Bid.create!(user: @user, auction: @won_auction_old, amount: BigDecimal("10.00"))
    @won_settlement_old = AuctionSettlement.create!(
      auction: @won_auction_old,
      winning_user: @user,
      winning_bid: @won_bid_old,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 3.days.ago,
      fulfillment_status: :pending
    )

    @won_auction_new = Auction.create!(
      title: "New Win",
      description: "desc",
      start_date: 4.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("24.00"),
      status: :ended,
      winning_user: @user
    )
    @won_bid_new = Bid.create!(user: @user, auction: @won_auction_new, amount: BigDecimal("25.00"))
    @won_settlement_new = AuctionSettlement.create!(
      auction: @won_auction_new,
      winning_user: @user,
      winning_bid: @won_bid_new,
      final_price: BigDecimal("25.00"),
      currency: "usd",
      status: :paid,
      ended_at: 1.day.ago,
      fulfillment_status: :shipped,
      fulfillment_address: { "line1" => "123 Main", "city" => "Portland", "region" => "OR", "postal" => "97201" },
      shipping_cost: BigDecimal("5.00"),
      shipping_carrier: "ups",
      tracking_number: "1Z999"
    )

    @other_auction = Auction.create!(
      title: "Other Win",
      description: "desc",
      start_date: 4.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("29.00"),
      status: :ended,
      winning_user: @other_user
    )
    other_bid = Bid.create!(user: @other_user, auction: @other_auction, amount: BigDecimal("30.00"))
    AuctionSettlement.create!(
      auction: @other_auction,
      winning_user: @other_user,
      winning_bid: other_bid,
      final_price: BigDecimal("30.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago,
      fulfillment_status: :pending
    )
  end

  test "GET /api/v1/me/wins returns only current user's wins (newest first)" do
    get "/api/v1/me/wins", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal [ @won_auction_new.id, @won_auction_old.id ], body.map { |row| row.fetch("auction_id") }
    assert_equal [ @won_settlement_new.id, @won_settlement_old.id ], body.map { |row| row.fetch("settlement_id") }
  end

  test "GET /api/v1/me/wins/:auction_id denies access to other user's win" do
    get "/api/v1/me/wins/#{@other_auction.id}", headers: auth_headers(@user, @session_token)
    assert_response :not_found
  end

  test "GET /api/v1/me/wins/:auction_id returns win details for current user" do
    get "/api/v1/me/wins/#{@won_auction_new.id}", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal @won_auction_new.id, body.fetch("auction_id")
    assert_equal @won_auction_new.title, body.fetch("auction_title")
    assert_equal @won_settlement_new.id, body.fetch("settlement_id")
    assert_equal "shipped", body.fetch("fulfillment_status")
    assert_equal @won_bid_new.id, body.dig("winning_bid", "id")
    assert_equal @won_bid_new.user_id, body.dig("winning_bid", "user_id")
    assert_equal "25.0", body.dig("winning_bid", "amount")
    assert_equal "ups", body.dig("fulfillment", "carrier")
    assert_equal "1Z999", body.dig("fulfillment", "tracking_number")
    assert_equal "5.0", body.dig("fulfillment", "shipping_cost")
    assert_equal "123 Main", body.dig("fulfillment", "address", "line1")
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
