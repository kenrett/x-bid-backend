require "test_helper"
require "jwt"

class AdminBidPacksApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      name: "Admin",
      email_address: "admin2@example.com",
      password: "password",
      role: :admin,
      bid_credits: 0
    )
    @session_token = SessionToken.create!(
      user: @admin,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )
  end

  test "soft deletes bid pack by deactivating it" do
    pack = BidPack.create!(name: "Gold", description: "desc", bids: 100, price: 10.0, active: true)

    delete "/api/v1/admin/bid-packs/#{pack.id}", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["active"]
    assert_equal pack.id, body["id"]
  end

  test "show returns bid pack data with pricePerBid" do
    pack = BidPack.create!(name: "Silver", description: "desc", bids: 50, price: 5.0, active: true)

    get "/api/v1/admin/bid-packs/#{pack.id}", headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Silver", body["name"]
    assert_equal "$0.10", body["pricePerBid"]
  end

  private

  def auth_headers
    payload = { user_id: @admin.id, session_token_id: @session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
