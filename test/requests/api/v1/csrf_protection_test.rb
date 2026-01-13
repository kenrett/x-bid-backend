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
end
