require "test_helper"
require "jwt"
require "uri"

class AccountExportApiTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/account/export returns a signed download URL when ready" do
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
      status: "applied"
    )
    CreditTransaction.create!(
      user: user,
      purchase: user.purchases.last,
      kind: :grant,
      amount: bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "export:#{SecureRandom.hex(6)}",
      metadata: {}
    )
    Purchase.create!(
      user: other,
      bid_pack: bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_export_2",
      status: "applied"
    )

    post "/api/v1/account/export", headers: auth_headers(user, session_token)
    assert_response :accepted

    get "/api/v1/account/export", headers: auth_headers(user, session_token)
    assert_response :success
    body = JSON.parse(response.body)
    export = body.fetch("export")
    assert_equal "ready", export["status"]
    assert export["download_url"].present?

    download_url = export.fetch("download_url")
    download_path = URI.parse(download_url).request_uri
    get download_path, headers: auth_headers(user, session_token)
    assert_response :success
    payload = JSON.parse(response.body)

    assert payload["user"].is_a?(Hash)
    assert_equal user.id, payload.dig("user", "id")

    purchases = payload.fetch("purchases")
    assert_equal 1, purchases.size
    assert_equal "pi_export_1", purchases.first["stripe_payment_intent_id"]

    bids = payload.fetch("bids")
    assert_equal 1, bids.size
    assert_equal user.id, Bid.find(bids.first.fetch("id")).user_id

    watches = payload.fetch("auction_watches")
    assert_equal 1, watches.size
    assert_equal user.id, AuctionWatch.find(watches.first.fetch("id")).user_id

    ledger_entries = payload.fetch("ledger_entries")
    assert_equal 1, ledger_entries.size
    assert_equal user.id, CreditTransaction.find(ledger_entries.first.fetch("id")).user_id
  end

  test "DELETE /api/v1/account revokes sessions and blocks future login" do
    user = User.create!(name: "User", email_address: "delete_user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("delete"), expires_at: 1.hour.from_now)

    delete "/api/v1/account",
           params: { current_password: "password", confirmation: "DELETE" },
           headers: auth_headers(user, session_token)
    assert_response :success
    user.reload
    assert user.disabled?
    assert_equal "Deleted User", user.name
    assert user.email_address.start_with?("deleted+")
    assert session_token.reload.revoked_at.present?

    post "/api/v1/login", params: { session: { email_address: "delete_user@example.com", password: "password" } }
    assert_response :unauthorized
    assert_equal "invalid_credentials", JSON.parse(response.body).dig("error", "code").to_s
  end

  test "DELETE /api/v1/account removes PII but preserves financial records" do
    user = User.create!(name: "User", email_address: "delete_pii@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("delete_pii"), expires_at: 1.hour.from_now)

    bid_pack = BidPack.create!(name: "Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)
    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_delete_pii",
      status: "applied"
    )
    credit_tx = CreditTransaction.create!(
      user: user,
      purchase: purchase,
      kind: :grant,
      amount: bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      metadata: {}
    )

    delete "/api/v1/account",
      params: { current_password: "password", confirmation: "DELETE" },
      headers: auth_headers(user, session_token)
    assert_response :success

    user.reload
    assert user.disabled?
    refute_equal "delete_pii@example.com", user.email_address
    assert_equal "Deleted User", user.name

    assert Purchase.find_by(id: purchase.id).present?
    assert CreditTransaction.find_by(id: credit_tx.id).present?
  end

  test "POST /api/v1/account/export is idempotent for recent exports" do
    user = User.create!(name: "User", email_address: "export_idempotent@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("export2"), expires_at: 1.hour.from_now)

    post "/api/v1/account/export", headers: auth_headers(user, session_token)
    assert_response :accepted
    first = JSON.parse(response.body).fetch("export")

    post "/api/v1/account/export", headers: auth_headers(user, session_token)
    assert_response :accepted
    second = JSON.parse(response.body).fetch("export")

    assert_equal first["id"], second["id"]
    assert_equal 1, user.account_exports.count
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    jwt = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{jwt}" }
  end
end
