require "test_helper"
require "jwt"

class MeActivityApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(
      user: @other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    @auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
  end

  test "GET /api/v1/me/activity returns only current user's activity" do
    Bid.create!(user: @user, auction: @auction, amount: BigDecimal("2.00"))
    Bid.create!(user: @other_user, auction: @auction, amount: BigDecimal("3.00"))
    AuctionWatch.create!(user: @user, auction: @auction)
    AuctionWatch.create!(user: @other_user, auction: @auction)

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    types = body.fetch("items").map { |item| item["type"] }.uniq
    assert_includes types, "bid_placed"
    assert_includes types, "auction_watched"

    assert_equal 2, body.fetch("items").length
  end

  test "activity contains bid item shape" do
    bid = Bid.create!(user: @user, auction: @auction, amount: BigDecimal("2.00"))

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    item = JSON.parse(response.body).fetch("items").first
    assert_equal "bid_placed", item["type"]
    assert item["created_at"].present?
    assert_equal @auction.id, item.dig("auction", "id")
    assert_equal @auction.title, item.dig("auction", "title")
    assert_equal @auction.external_status, item.dig("auction", "status")
    assert_equal bid.id, item.dig("data", "bid_id")
    assert_equal "2.0", item.dig("data", "amount")
  end

  test "activity contains outcome items when auctions close" do
    ended_auction = Auction.create!(
      title: "Ended",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("1.00"),
      status: :ended,
      winning_user: @other_user
    )
    Bid.create!(user: @user, auction: ended_auction, amount: BigDecimal("2.00"))

    won_auction = Auction.create!(
      title: "Won",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("1.00"),
      status: :ended,
      winning_user: @user
    )

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    types = body.fetch("items").map { |item| item["type"] }
    assert_includes types, "auction_lost"
    assert_includes types, "auction_won"
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
