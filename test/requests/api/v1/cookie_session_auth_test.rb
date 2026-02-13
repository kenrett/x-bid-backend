require "test_helper"

class CookieSessionAuthTest < ActionDispatch::IntegrationTest
  test "host-only cookie auth does not cross subdomains" do
    user = User.create!(
      name: "Cookie User",
      email_address: "cookie-auth@example.com",
      password: "password",
      bid_credits: 0
    )

    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      host! "api.lvh.me"
      https!
      post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
      assert_response :success

      host! "store.lvh.me"
      get "/api/v1/me"
      assert_response :unauthorized
    end
  end

  test "bearer still works when cookie absent" do
    user = create_actor(role: :user)
    get "/api/v1/me", headers: auth_headers_for(user)

    assert_response :success
  end

  test "invalid session cookie returns unknown_session reason" do
    get "/api/v1/me", headers: { "Cookie" => "bs_session_id=bogus" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "unknown_session", body.dig("error", "details", "reason")
  end
end
