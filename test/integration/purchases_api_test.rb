require "test_helper"
require "jwt"

class PurchasesApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(
      user: @other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    @bid_pack = BidPack.create!(
      name: "Starter",
      bids: 10,
      price: BigDecimal("9.99"),
      highlight: false,
      description: "test pack",
      active: true
    )
  end

  test "GET /api/v1/me/purchases returns only current user's purchases (newest first)" do
    older = create_purchase(user: @user, status: "pending", created_at: 2.days.ago)
    newer = create_purchase(user: @user, status: "completed", created_at: 1.day.ago)
    create_purchase(user: @other_user, status: "completed", created_at: 1.hour.ago)

    get "/api/v1/me/purchases", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert body.is_a?(Array)
    assert_equal 2, body.length
    assert_equal newer.id, body[0]["id"]
    assert_equal older.id, body[1]["id"]
    assert_equal "completed", body[0]["status"]
    assert_equal "pending", body[1]["status"]

    assert_equal (@bid_pack.price * 100).to_i, body[0]["amount_cents"]
    assert_equal "usd", body[0]["currency"]
    assert_equal @bid_pack.id, body[0].dig("bid_pack", "id")
    assert_equal @bid_pack.name, body[0].dig("bid_pack", "name")
    assert_equal @bid_pack.bids, body[0].dig("bid_pack", "credits")
    assert_equal (@bid_pack.price * 100).to_i, body[0].dig("bid_pack", "price_cents")
  end

  test "GET /api/v1/me/purchases/:id denies access to other user's purchase" do
    purchase = create_purchase(user: @other_user, status: "completed")

    get "/api/v1/me/purchases/#{purchase.id}", headers: auth_headers(@user, @session_token)

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s
  end

  test "GET /api/v1/me/purchases/:id returns purchase detail for current user" do
    purchase = create_purchase(user: @user, status: "failed")

    get "/api/v1/me/purchases/#{purchase.id}", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase.id, body["id"]
    assert_equal "failed", body["payment_status"]
    assert_equal "failed", body["status"]
    assert_equal @bid_pack.bids, body["credits_added"]
    assert_nil body["ledger_grant_entry_id"]
    assert_equal purchase.stripe_checkout_session_id, body["stripe_checkout_session_id"]
    assert_equal purchase.stripe_payment_intent_id, body["stripe_payment_intent_id"]
    assert_equal @bid_pack.id, body.dig("bid_pack", "id")
    assert_nil body.dig("bid_pack", "sku")
  end

  private

  def create_purchase(user:, status:, created_at: Time.current)
    Purchase.create!(
      user: user,
      bid_pack: @bid_pack,
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      stripe_checkout_session_id: SecureRandom.uuid,
      stripe_payment_intent_id: SecureRandom.uuid,
      status: status,
      created_at: created_at
    )
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
