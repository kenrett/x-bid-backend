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
        start_date: Time.current.iso8601,
        end_time: 1.day.from_now.iso8601,
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

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_includes body["error"], "Cannot retire an auction that has bids"
  end

  test "retires auction without bids and returns no content" do
    auction = Auction.create!(
      title: "Retire Cleanly",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )

    delete "/api/v1/auctions/#{auction.id}", headers: auth_headers

    assert_response :no_content
    assert_equal "inactive", auction.reload.status
  end

  test "returns an error when retiring an already inactive auction" do
    auction = Auction.create!(
      title: "Already Inactive",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    delete "/api/v1/auctions/#{auction.id}", headers: auth_headers

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "Auction already inactive", body["error"]
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

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_includes body["error"], "Invalid status"
  end

  test "blocks hard delete through the model" do
    auction = Auction.create!(
      title: "Do Not Delete",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )

    assert_no_difference("Auction.count") do
      assert_not auction.destroy
    end

    assert_includes auction.errors.full_messages, "Auctions cannot be hard-deleted; retire instead"
    assert_equal "active", auction.reload.status
  end

  private

  def auth_headers
    payload = { user_id: @admin.id, session_token_id: @session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
