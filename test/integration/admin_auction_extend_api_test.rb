require "test_helper"
require "jwt"

class AdminAuctionExtendApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      name: "Admin",
      email_address: "admin_extend_api@example.com",
      password: "password",
      role: :admin,
      bid_credits: 0
    )
    @user = User.create!(
      name: "User",
      email_address: "user_extend_api@example.com",
      password: "password",
      role: :user,
      bid_credits: 0
    )
    @admin_session = SessionToken.create!(
      user: @admin,
      token_digest: SessionToken.digest("raw-admin"),
      expires_at: 1.hour.from_now
    )
    @user_session = SessionToken.create!(
      user: @user,
      token_digest: SessionToken.digest("raw-user"),
      expires_at: 1.hour.from_now
    )
  end

  test "admin extends an auction within the window" do
    auction = Auction.create!(
      title: "Extendable Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 10.seconds.from_now,
      current_price: 1.0,
      status: :active
    )
    original_end_time = auction.end_time

    post "/api/v1/auctions/#{auction.id}/extend_time", headers: auth_headers(@admin, @admin_session)

    assert_response :ok
    body = JSON.parse(response.body)
    new_end_time = Time.iso8601(body["end_time"])
    assert new_end_time > original_end_time
  end

  test "rejects non-admin user" do
    auction = Auction.create!(
      title: "Restricted Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 10.seconds.from_now,
      current_price: 1.0,
      status: :active
    )

    post "/api/v1/auctions/#{auction.id}/extend_time", headers: auth_headers(@user, @user_session)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error_code"]
  end

  test "returns invalid_state when auction is outside the extend window" do
    auction = Auction.create!(
      title: "Too Far Out",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )

    post "/api/v1/auctions/#{auction.id}/extend_time", headers: auth_headers(@admin, @admin_session)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_state", body["error_code"]
  end

  test "returns not_found for missing auction" do
    post "/api/v1/auctions/999999/extend_time", headers: auth_headers(@admin, @admin_session)

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body["error_code"]
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
