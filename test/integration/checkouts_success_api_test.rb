require "test_helper"
require "jwt"

class CheckoutsSuccessApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name: "Buyer",
      email_address: "buyer@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    @session_token = SessionToken.create!(
      user: @user,
      token_digest: SessionToken.digest("raw"),
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

  test "returns pending status without mutating credits or ledger" do
    purchase = create_purchase(status: "created", stripe_checkout_session_id: "cs_pending")
    credits_before = @user.bid_credits
    status_before = purchase.status

    assert_no_difference("CreditTransaction.count") do
      assert_no_difference("MoneyEvent.count") do
        get "/api/v1/checkout/success", params: { session_id: "cs_pending" }, headers: auth_headers(@user, @session_token)
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_equal purchase.id, body["purchase_id"]
    assert_equal credits_before, @user.reload.bid_credits
    assert_equal status_before, purchase.reload.status
  end

  test "returns applied status once purchase is applied" do
    purchase = create_purchase(status: "applied", stripe_checkout_session_id: "cs_applied", applied_at: Time.current)

    get "/api/v1/checkout/success", params: { session_id: "cs_applied" }, headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "applied", body["status"]
    assert_equal purchase.id, body["purchase_id"]
  end

  test "returns failed status for failed purchases" do
    purchase = create_purchase(status: "failed", stripe_checkout_session_id: "cs_failed")

    get "/api/v1/checkout/success", params: { session_id: "cs_failed" }, headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "failed", body["status"]
    assert_equal purchase.id, body["purchase_id"]
  end

  test "returns 404 for purchases owned by another user" do
    other_user = User.create!(
      name: "Other",
      email_address: "other@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    other_token = SessionToken.create!(user: other_user, token_digest: SessionToken.digest("raw2"), expires_at: 1.hour.from_now)

    create_purchase(status: "created", stripe_checkout_session_id: "cs_other", user: @user)

    get "/api/v1/checkout/success", params: { session_id: "cs_other" }, headers: auth_headers(other_user, other_token)

    assert_response :not_found
  end

  test "returns 404 for unknown checkout session id" do
    get "/api/v1/checkout/success", params: { session_id: "cs_missing" }, headers: auth_headers(@user, @session_token)

    assert_response :not_found
  end

  private

  def create_purchase(status:, stripe_checkout_session_id:, user: @user, applied_at: nil)
    Purchase.create!(
      user: user,
      bid_pack: @bid_pack,
      amount_cents: (@bid_pack.price.to_d * 100).to_i,
      currency: "usd",
      stripe_checkout_session_id: stripe_checkout_session_id,
      status: status,
      applied_at: applied_at
    )
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
