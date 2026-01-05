require "test_helper"

class AuthContractV1Test < ActionDispatch::IntegrationTest
  test "POST /api/v1/login returns the full v1 shape" do
    user = User.create!(
      name: "User",
      email_address: "login_contract@example.com",
      password: "password",
      bid_credits: 0
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_auth_v1_shape!(body, label: "POST /api/v1/login response")
  end

  test "POST /api/v1/session/refresh returns the full v1 shape and rotates refresh tokens" do
    user = User.create!(
      name: "User",
      email_address: "refresh_contract@example.com",
      password: "password",
      bid_credits: 0
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }
    assert_response :success
    refresh_body = JSON.parse(response.body)
    assert_auth_v1_shape!(refresh_body, label: "POST /api/v1/session/refresh response")

    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }
    assert_response :unauthorized
  end

  test "refresh fails after logout/revocation" do
    user = User.create!(
      name: "User",
      email_address: "refresh_after_logout@example.com",
      password: "password",
      bid_credits: 0
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    delete "/api/v1/logout", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }
    assert_response :success

    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }
    assert_response :unauthorized
  end

  test "refresh fails with invalid or expired refresh token" do
    user = User.create!(
      name: "User",
      email_address: "invalid_refresh_token@example.com",
      password: "password",
      bid_credits: 0
    )

    post "/api/v1/session/refresh", params: { refresh_token: "not-a-real-token" }
    assert_response :unauthorized

    _expired_session_token, expired_refresh_token = SessionToken.generate_for(user: user, ttl: -1.second)
    post "/api/v1/session/refresh", params: { refresh_token: expired_refresh_token }
    assert_response :unauthorized
  end

  test "GET /api/v1/me fails after revocation" do
    user = User.create!(
      name: "User",
      email_address: "me_after_logout@example.com",
      password: "password",
      bid_credits: 0
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    delete "/api/v1/logout", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }
    assert_response :success

    get "/api/v1/me", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }
    assert_response :unauthorized
  end

  private

  def bearer(access_token)
    "Bearer #{access_token}"
  end

  def assert_auth_v1_shape!(hash, label:)
    assert_exact_keys!(
      hash,
      %w[access_token refresh_token session_token_id user],
      label: label
    )
    assert hash["access_token"].is_a?(String), "#{label} expected access_token to be a String"
    assert hash["refresh_token"].is_a?(String), "#{label} expected refresh_token to be a String"
  end

  def assert_exact_keys!(hash, expected_keys, label:)
    actual_keys = hash.keys.map(&:to_s).sort
    expected_keys = expected_keys.map(&:to_s).sort

    extra = actual_keys - expected_keys
    missing = expected_keys - actual_keys

    assert_equal(
      expected_keys,
      actual_keys,
      "#{label} keys mismatch.\nExpected: #{expected_keys}\nActual:   #{actual_keys}\nMissing:  #{missing}\nExtra:    #{extra}"
    )
  end
end
