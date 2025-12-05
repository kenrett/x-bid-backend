require "test_helper"
require "jwt"

class SessionsApiContractTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
  end

  test "POST /api/v1/login returns token and flags" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert_equal false, body["is_admin"]
    assert_equal false, body["is_superuser"]
  end

  test "GET /api/v1/session/remaining returns remaining time" do
    get "/api/v1/session/remaining", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["seconds_remaining"].is_a?(Numeric)
    assert_equal @session_token.id, body["session_token_id"]
  end

  test "DELETE /api/v1/logout revokes token" do
    delete "/api/v1/logout", headers: auth_headers(@user, @session_token)

    assert_response :success
    assert @session_token.reload.revoked_at.present?
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
