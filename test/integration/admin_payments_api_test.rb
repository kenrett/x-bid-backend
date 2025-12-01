require "test_helper"
require "jwt"

class AdminPaymentsApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      name: "Admin",
      email_address: "admin@example.com",
      password: "password",
      role: :admin,
      bid_credits: 0
    )
    @admin_session = SessionToken.create!(
      user: @admin,
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

  test "returns payments for admins" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    get "/api/v1/admin/payments", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size

    payment = body.first
    assert_equal purchase.id, payment["id"]
    assert_equal user.email_address, payment["user_email"]
    assert_in_delta @bid_pack.price.to_f, payment["amount"].to_f, 0.001
    assert_equal purchase.status, payment["status"]
    assert payment["created_at"].present?
  end

  test "filters payments by user email search" do
    matching_user = create_user(email: "match@example.com")
    other_user = create_user(email: "other@example.com")
    create_purchase(user: matching_user)
    create_purchase(user: other_user)

    get "/api/v1/admin/payments", params: { search: "match" }, headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal matching_user.email_address, body.first["user_email"]
  end

  test "rejects non-admins" do
    user = create_user(email: "user@example.com", role: :user)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    get "/api/v1/admin/payments", headers: auth_headers(user, session_token)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "Admin privileges required", body["error"]
  end

  private

  def create_user(email:, role: :user)
    User.create!(
      name: "User",
      email_address: email,
      password: "password",
      role: role,
      bid_credits: 0
    )
  end

  def create_purchase(user:)
    Purchase.create!(
      user: user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: SecureRandom.uuid,
      status: "completed"
    )
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
