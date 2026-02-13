require "test_helper"

class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "CSRF User",
      email_address: "csrf-user@example.com",
      password: "password",
      bid_credits: 0
    )
  end

  test "POST without X-CSRF-Token fails with csrf_failed" do
    host! "api.lvh.me"
    post "/api/v1/login",
         params: { session: { email_address: @user.email_address, password: "password" } },
         headers: { "Origin" => "http://app.lvh.me:5173" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "csrf_failed", body.dig("error", "details", "reason")
  end

  test "POST with junk Authorization header still fails with csrf_failed" do
    host! "api.lvh.me"
    post "/api/v1/login",
         params: { session: { email_address: @user.email_address, password: "password" } },
         headers: {
           "Origin" => "http://app.lvh.me:5173",
           "Authorization" => "Bearer junk"
         }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "csrf_failed", body.dig("error", "details", "reason")
  end

  test "POST with valid CSRF token succeeds" do
    host! "api.lvh.me"
    get "/api/v1/csrf", headers: { "Origin" => "http://app.lvh.me:5173" }
    assert_response :success
    token = JSON.parse(response.body).fetch("csrf_token")

    post "/api/v1/login",
         params: { session: { email_address: @user.email_address, password: "password" } },
         headers: {
           "Origin" => "http://app.lvh.me:5173",
           "X-CSRF-Token" => token
         }

    assert_response :success
  end

  test "POST with mismatched CSRF token fails with csrf_failed" do
    host! "api.lvh.me"
    get "/api/v1/csrf", headers: { "Origin" => "http://app.lvh.me:5173" }
    assert_response :success

    post "/api/v1/login",
         params: { session: { email_address: @user.email_address, password: "password" } },
         headers: {
           "Origin" => "http://app.lvh.me:5173",
           "X-CSRF-Token" => "bad-token"
         }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "csrf_failed", body.dig("error", "details", "reason")
  end

  test "cookie-authenticated unsafe request still requires CSRF with junk Authorization" do
    host! "api.lvh.me"
    get "/api/v1/csrf", headers: { "Origin" => "http://app.lvh.me:5173" }
    assert_response :success
    token = JSON.parse(response.body).fetch("csrf_token")

    post "/api/v1/login",
         params: { session: { email_address: @user.email_address, password: "password" } },
         headers: {
           "Origin" => "http://app.lvh.me:5173",
           "X-CSRF-Token" => token
         }
    assert_response :success

    delete "/api/v1/logout",
           headers: {
             "Origin" => "http://app.lvh.me:5173",
             "Authorization" => "Bearer junk"
           }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "csrf_failed", body.dig("error", "details", "reason")
  end

  test "valid bearer auth skips CSRF without browser session cookie" do
    host! "api.lvh.me"
    session_token = SessionToken.create!(
      user: @user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
    payload = { user_id: @user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)

    delete "/api/v1/logout",
           headers: {
             "Origin" => "http://app.lvh.me:5173",
             "Authorization" => "Bearer #{token}"
           }

    assert_response :success
  end
end
