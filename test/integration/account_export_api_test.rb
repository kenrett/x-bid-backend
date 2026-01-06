require "test_helper"
require "jwt"

class AccountExportApiTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/account/export returns purchases, bids, and auction watches" do
    user = User.create!(name: "User", email_address: "export_user@example.com", password: "password", bid_credits: 0)
    other = User.create!(name: "Other", email_address: "export_other@example.com", password: "password", bid_credits: 0)

    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("export"), expires_at: 1.hour.from_now)

    auction = Auction.create!(
      title: "Watched",
      description: "Desc",
      start_date: 1.hour.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
    AuctionWatch.create!(user: user, auction: auction)
    AuctionWatch.create!(user: other, auction: auction)

    Bid.create!(user: user, auction: auction, amount: BigDecimal("2.00"))
    Bid.create!(user: other, auction: auction, amount: BigDecimal("3.00"))

    bid_pack = BidPack.create!(name: "Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)
    Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_export_1",
      status: "completed"
    )
    Purchase.create!(
      user: other,
      bid_pack: bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_export_2",
      status: "completed"
    )

    get "/api/v1/account/export", headers: auth_headers(user, session_token)
    assert_response :success
    body = JSON.parse(response.body)

    assert body["user"].is_a?(Hash)
    assert_equal user.id, body.dig("user", "id")

    purchases = body.fetch("purchases")
    assert_equal 1, purchases.size
    assert_equal "pi_export_1", purchases.first["stripe_payment_intent_id"]

    bids = body.fetch("bids")
    assert_equal 1, bids.size
    assert_equal user.id, Bid.find(bids.first.fetch("id")).user_id

    watches = body.fetch("auction_watches")
    assert_equal 1, watches.size
    assert_equal user.id, AuctionWatch.find(watches.first.fetch("id")).user_id
  end

  test "DELETE /api/v1/account revokes sessions and blocks future login" do
    user = User.create!(name: "User", email_address: "delete_user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("delete"), expires_at: 1.hour.from_now)

    delete "/api/v1/account",
           params: { current_password: "password", confirmation: "DELETE" },
           headers: auth_headers(user, session_token)
    assert_response :success
    assert user.reload.disabled?
    assert session_token.reload.revoked_at.present?

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :forbidden
    assert_equal "account_disabled", JSON.parse(response.body).dig("error", "code").to_s
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    jwt = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{jwt}" }
  end
end
