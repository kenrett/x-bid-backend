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
    assert body["access_token"].present?
    assert_equal false, body.dig("user", "is_admin")
    assert_equal false, body.dig("user", "is_superuser")
  end

  test "POST /api/v1/login accepts flat payload (email_address/password)" do
    post "/api/v1/login", params: { email_address: @user.email_address, password: "password" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["session_token_id"].present?
  end

  test "POST /api/v1/session/refresh accepts flat payload (refresh_token)" do
    session_token, refresh_token = SessionToken.generate_for(user: @user)

    headers = csrf_headers
    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }, headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["session_token_id"].present?
  ensure
    session_token&.destroy
  end

  test "GET /api/v1/session/remaining returns remaining time" do
    get "/api/v1/session/remaining", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert body["remaining_seconds"].is_a?(Numeric)
    assert body["remaining_seconds"] > 0
    assert_equal @session_token.id, body["session_token_id"]
    assert body["session_expires_at"].present?
    assert_equal @user.id, body.dig("user", "id")
    assert_equal false, body["is_admin"]
    assert_equal false, body["is_superuser"]
  end

  test "GET /api/v1/session/remaining returns 401 when session is expired" do
    expired_session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("expired"), expires_at: 1.hour.ago)
    headers = auth_headers(@user, expired_session_token, exp: 1.hour.from_now.to_i)

    get "/api/v1/session/remaining", headers: headers

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_session", body.dig("error", "code").to_s
  end

  test "GET /api/v1/session/remaining returns 401 when JWT exp is expired" do
    get "/api/v1/session/remaining", headers: auth_headers(@user, @session_token, exp: 1.hour.ago.to_i)

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code").to_s
    assert_equal "Token has expired", body.dig("error", "message")
  end

  test "GET /api/v1/session/remaining returns 401 when session is revoked" do
    revoked_session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("revoked"), expires_at: 1.hour.from_now)
    revoked_session_token.revoke!
    headers = auth_headers(@user, revoked_session_token)

    get "/api/v1/session/remaining", headers: headers

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_session", body.dig("error", "code").to_s
  end

  test "GET /api/v1/session/remaining returns 403 when user is disabled" do
    disabled_user = User.create!(name: "Disabled", email_address: "disabled@example.com", password: "password", status: :disabled, bid_credits: 0)
    session_token = SessionToken.create!(user: disabled_user, token_digest: SessionToken.digest("disabled"), expires_at: 1.hour.from_now)

    get "/api/v1/session/remaining", headers: auth_headers(disabled_user, session_token)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "account_disabled", body.dig("error", "code").to_s
  end

  test "DELETE /api/v1/logout revokes token" do
    delete "/api/v1/logout", headers: auth_headers(@user, @session_token)

    assert_response :success
    assert @session_token.reload.revoked_at.present?
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
