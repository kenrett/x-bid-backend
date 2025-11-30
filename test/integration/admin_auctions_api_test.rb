require "test_helper"
require "jwt"

class AdminAuctionsApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      name: "Admin",
      email_address: "admin@example.com",
      password: "password",
      role: :admin,
      bid_credits: 0
    )
    @session_token = SessionToken.create!(
      user: @admin,
      token_digest: SessionToken.digest("raw"),
      expires_at: 1.hour.from_now
    )
  end

  test "creates auction with external status mapping" do
    payload = {
      auction: {
        title: "Test Auction",
        description: "Desc",
        start_date: Time.current.to_s(:db),
        end_time: 1.day.from_now.to_s(:db),
        current_price: 10.0,
        status: "scheduled"
      }
    }

    post "/api/v1/auctions", params: payload, headers: auth_headers

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "scheduled", body["status"]
    assert_equal "Test Auction", body["title"]
  end

  test "rejects retiring auction with bids" do
    auction = Auction.create!(
      title: "Retire Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )
    bidder = User.create!(
      name: "Bidder",
      email_address: "bidder@example.com",
      password: "password",
      bid_credits: 0
    )
    Bid.create!(user: bidder, auction: auction, amount: 2.0)

    delete "/api/v1/auctions/#{auction.id}", headers: auth_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "Cannot retire an auction that has bids"
  end

  test "invalid status returns 422" do
    auction = Auction.create!(
      title: "Update Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    put "/api/v1/auctions/#{auction.id}", params: { auction: { status: "not-a-status" } }, headers: auth_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "Invalid status"
  end

  private

  def auth_headers
    payload = { user_id: @admin.id, session_token_id: @session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
