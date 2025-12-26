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
      reason: "seed",
      idempotency_key: "test:wallet:grant",
      metadata: {}
    )
    CreditTransaction.create!(
      user: @user,
      kind: :debit,
      amount: -2,
      reason: "bid",
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
    assert_equal "grant", body["transactions"][0]["kind"]
    assert_equal 5, body["transactions"][0]["amount"]
    assert_equal "mine", body["transactions"][0]["reason"]
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
    assert_equal "t0", body["transactions"][0]["reason"]

    get "/api/v1/wallet/transactions", params: { page: 2 }, headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 5, body["transactions"].length
    assert_equal 2, body["page"]
    assert_equal 25, body["per_page"]
    assert_equal false, body["has_more"]
    assert_equal "t25", body["transactions"][0]["reason"]
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
