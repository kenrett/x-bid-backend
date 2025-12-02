require "test_helper"
require "jwt"

class AdminAuditApiTest < ActionDispatch::IntegrationTest
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

  test "creates audit log via endpoint" do
    post "/api/v1/admin/audit", params: {
      audit: {
        action: "custom.test",
        target_type: "User",
        target_id: @admin.id,
        payload: { example: true }
      }
    }, headers: auth_headers(@admin, @session_token), as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]

    log = AuditLog.order(created_at: :desc).first
    assert_equal "custom.test", log.action
    assert_equal @admin.id, log.actor_id
    assert_equal "User", log.target_type
    assert_equal @admin.id, log.target_id
    assert_equal true, log.payload["example"]
  end

  test "rejects unauthenticated requests" do
    post "/api/v1/admin/audit", params: { audit: { action: "custom.test" } }
    assert_response :unauthorized
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
