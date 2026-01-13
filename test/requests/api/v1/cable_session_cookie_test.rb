require "test_helper"

class CableSessionCookieTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "User",
      email_address: "cable-cookie@example.com",
      password: "password",
      bid_credits: 0
    )
  end

  test "login sets cable session cookie with expected flags" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }

    assert_response :success
    set_cookie = set_cookie_header
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_includes set_cookie, "cable_session="
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
  end

  test "signup sets cable session cookie with expected flags" do
    post "/api/v1/signup", params: {
      user: {
        name: "Signup User",
        email_address: "signup-cookie@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_response :created
    set_cookie = set_cookie_header
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_includes set_cookie, "cable_session="
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
  end

  test "refresh sets cable session cookie with expected flags" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    headers = csrf_headers
    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }, headers: headers

    assert_response :success
    set_cookie = set_cookie_header
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_includes set_cookie, "cable_session="
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
  end

  test "login sets Secure on cable session cookie in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_includes set_cookie, "cable_session="
    assert_match(/secure/i, set_cookie)
  end

  test "logout clears cable session cookie" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    delete "/api/v1/logout", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }

    assert_response :success
    set_cookie = set_cookie_header
    assert_includes set_cookie, "cable_session="
    assert_match(/path=\/cable/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/expires=/i, set_cookie)
  end

  private

  def bearer(access_token)
    "Bearer #{access_token}"
  end

  def set_cookie_header
    header = response.headers["Set-Cookie"]
    return header.join("\n") if header.is_a?(Array)

    header.to_s
  end
end
