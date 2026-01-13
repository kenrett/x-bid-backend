require "test_helper"
require "json"

class SessionEndpointResponseKeysTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/logged_in returns status payload (not UserSession) with exact top-level keys" do
    user = create_actor(role: :user)
    get "/api/v1/logged_in", headers: auth_headers_for(user)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal(
      %w[
        is_admin
        is_superuser
        logged_in
        redirect_path
        seconds_remaining
        session
        session_expires_at
        session_token_id
        user
      ].sort,
      body.keys.sort
    )
  end

  test "POST /api/v1/login returns access_token (not token) with exact top-level keys" do
    user = User.create!(
      name: "Session Keys",
      email_address: "session_keys_login@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal %w[access_token refresh_token session_token_id user].sort, body.keys.sort
    assert body.key?("access_token"), "Expected response to include access_token"
    refute body.key?("token"), "Expected response not to include legacy token"
  end

  test "POST /api/v1/signup returns access_token (not token) with exact top-level keys" do
    post "/api/v1/signup",
         params: {
           user: {
             name: "Session Keys",
             email_address: "session_keys_signup@example.com",
             password: "password",
             password_confirmation: "password"
           }
         }

    assert_response :created

    body = JSON.parse(response.body)
    assert_equal %w[access_token refresh_token session_token_id user].sort, body.keys.sort
    assert body.key?("access_token"), "Expected response to include access_token"
    refute body.key?("token"), "Expected response not to include legacy token"
  end

  test "POST /api/v1/session/refresh returns access_token (not token) with exact top-level keys" do
    user = User.create!(
      name: "Session Keys",
      email_address: "session_keys_refresh@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    headers = csrf_headers
    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal %w[access_token refresh_token session_token_id user].sort, body.keys.sort
    assert body.key?("access_token"), "Expected response to include access_token"
    refute body.key?("token"), "Expected response not to include legacy token"
  end
end
