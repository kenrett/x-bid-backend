require "test_helper"
require "jwt"

class WalletApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
  end

  test "GET /api/v1/wallet returns balance and audit" do
    CreditTransaction.create!(
      user: @user,
      kind: :grant,
      amount: 10,
      reason: "seed_grant",
      idempotency_key: "test:wallet:grant",
      metadata: {}
    )
    CreditTransaction.create!(
      user: @user,
      kind: :debit,
      amount: -2,
      reason: "bid_placed",
      idempotency_key: "test:wallet:debit",
      metadata: {}
    )

    @user.update!(bid_credits: 8)

    get "/api/v1/wallet", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 8, body["credits_balance"]
    assert_equal "ledger_derived", body["balance_source"]
    assert_equal({ "cached" => 8, "derived" => 8, "matches" => true }, body["balance_audit"])
    assert body["as_of"].present?
  end

  test "GET /api/v1/wallet/transactions returns only current user's entries" do
    mine = CreditTransaction.create!(
      user: @user,
      kind: :grant,
      amount: 5,
      reason: "mine",
      idempotency_key: "test:wallet:mine",
      metadata: { "a" => 1 }
    )
    CreditTransaction.create!(
      user: @other_user,
      kind: :grant,
      amount: 100,
      reason: "theirs",
      idempotency_key: "test:wallet:theirs",
      metadata: {}
    )

    get "/api/v1/wallet/transactions", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 1, body["transactions"].length
    assert_equal mine.id, body["transactions"][0]["id"]
    assert_equal "credit", body["transactions"][0]["kind"]
    assert_equal 5, body["transactions"][0]["amount"]
    assert_equal "Mine", body["transactions"][0]["reason"]
    assert_equal "mine", body["transactions"][0]["reason_code"]
    assert_nil body["transactions"][0]["reference_type"]
    assert_nil body["transactions"][0]["reference_id"]
    assert body["transactions"][0]["occurred_at"].present?
    assert_equal "test:wallet:mine", body["transactions"][0]["idempotency_key"]
    assert_equal({ "a" => 1 }, body["transactions"][0]["metadata"])
  end

  test "GET /api/v1/wallet/transactions paginates and orders newest-first" do
    29.downto(0) do |i|
      CreditTransaction.create!(
        user: @user,
        kind: :grant,
        amount: 1,
        reason: "t#{i}",
        idempotency_key: "test:wallet:page:#{i}",
        metadata: {}
      )
    end

    get "/api/v1/wallet/transactions", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 25, body["transactions"].length
    assert_equal 1, body["page"]
    assert_equal 25, body["per_page"]
    assert_equal true, body["has_more"]
    assert_equal "T0", body["transactions"][0]["reason"]

    get "/api/v1/wallet/transactions", params: { page: 2 }, headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 5, body["transactions"].length
    assert_equal 2, body["page"]
    assert_equal 25, body["per_page"]
    assert_equal false, body["has_more"]
    assert_equal "T25", body["transactions"][0]["reason"]
  end

  test "wallet transactions use canonical kind/amount and include reason_code + references" do
    auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 100, price: 1.0, active: true)
    purchase = Purchase.create!(user: @user, bid_pack: bid_pack, status: "completed", amount_cents: 100, currency: "usd")

    admin = User.create!(name: "Admin", email_address: "admin_wallet@example.com", password: "password", role: :admin, bid_credits: 0)

    # Newest first
    CreditTransaction.create!(
      user: @user,
      kind: :adjustment,
      amount: -7,
      reason: "admin_adjustment",
      idempotency_key: "test:wallet:adj",
      admin_actor: admin,
      created_at: 1.hour.ago,
      metadata: {}
    )
    CreditTransaction.create!(
      user: @user,
      kind: :debit,
      amount: -1,
      reason: "bid_placed",
      idempotency_key: "test:wallet:bid",
      auction: auction,
      created_at: 2.hours.ago,
      metadata: {}
    )
    CreditTransaction.create!(
      user: @user,
      kind: :grant,
      amount: 100,
      reason: "bid_pack_purchase",
      idempotency_key: "test:wallet:purchase_grant",
      purchase: purchase,
      created_at: 3.hours.ago,
      metadata: {}
    )
    CreditTransaction.create!(
      user: @user,
      kind: :debit,
      amount: -25,
      reason: "purchase_refund_credit_reversal",
      idempotency_key: "test:wallet:refund_reversal",
      purchase: purchase,
      created_at: 4.hours.ago,
      metadata: {}
    )

    get "/api/v1/wallet/transactions", headers: auth_headers(@user, @session_token)
    assert_response :success
    rows = JSON.parse(response.body).fetch("transactions")

    assert_equal %w[admin_adjustment bid_placed bid_pack_purchase purchase_refund_credit_reversal], rows.map { |row| row.fetch("reason_code") }
    assert_equal %w[debit debit credit debit], rows.map { |row| row.fetch("kind") }
    assert_equal [ 7, 1, 100, 25 ], rows.map { |row| row.fetch("amount") }

    assert_equal "Admin adjustment", rows[0].fetch("reason")
    assert_equal admin.id, rows[0].fetch("admin_actor_id")

    assert_equal "Bid placed", rows[1].fetch("reason")
    assert_equal "Auction", rows[1].fetch("reference_type")
    assert_equal auction.id, rows[1].fetch("reference_id")

    assert_equal "Bid pack purchase", rows[2].fetch("reason")
    assert_equal "Purchase", rows[2].fetch("reference_type")
    assert_equal purchase.id, rows[2].fetch("reference_id")

    assert_equal "Refund", rows[3].fetch("reason")
    assert_equal "Purchase", rows[3].fetch("reference_type")
    assert_equal purchase.id, rows[3].fetch("reference_id")
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
