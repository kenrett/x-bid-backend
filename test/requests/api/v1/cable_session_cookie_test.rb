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
    set_cookie = cookie_header_for("cable_session")
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
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
    set_cookie = cookie_header_for("cable_session")
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
  end

  test "refresh sets cable session cookie with expected flags" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)

    headers = csrf_headers
    post "/api/v1/session/refresh", params: { refresh_token: login_body.fetch("refresh_token") }, headers: headers

    assert_response :success
    set_cookie = cookie_header_for("cable_session")
    assert set_cookie.present?, "Expected Set-Cookie header to be present"
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
  end

  test "login sets Secure on cable session cookie in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success
    set_cookie = cookie_header_for("cable_session")
    assert_match(/secure/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
  end

  test "login keeps SameSite=Lax on cable session cookie when none is requested" do
    with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => "true") do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        host! "api.biddersweet.app"
        https!
        post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
      end
    end

    assert_response :success
    set_cookie = cookie_header_for("cable_session")
    assert_match(/secure/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
  end

  test "logout clears cable session cookie" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)
    logout_headers = csrf_headers.merge("Authorization" => bearer(login_body.fetch("access_token")))

    SessionEventBroadcaster.stub(:session_invalidated, nil) do
      delete "/api/v1/logout", headers: logout_headers
    end

    assert_response :success
    set_cookie = cookie_header_for("cable_session")
    assert_match(/cable_session=;?/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_expired_cookie!(set_cookie)
  end

  test "logout clears cable session cookie with production attributes" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
      assert_response :success
      login_body = JSON.parse(response.body)
      logout_headers = csrf_headers.merge("Authorization" => bearer(login_body.fetch("access_token")))

      SessionEventBroadcaster.stub(:session_invalidated, nil) do
        delete "/api/v1/logout", headers: logout_headers
      end
    end

    assert_response :success
    set_cookie = cookie_header_for("cable_session")
    assert_match(/cable_session=;?/i, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/path=\/cable/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/secure/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
    assert_expired_cookie!(set_cookie)
  end

  private

  def bearer(access_token)
    "Bearer #{access_token}"
  end

  def set_cookie_headers
    if response.headers.respond_to?(:get_all)
      values = response.headers.get_all("Set-Cookie")
      return values if values.present?
    end

    header = response.headers["Set-Cookie"]
    return [] if header.blank?
    return header if header.is_a?(Array)

    header.split("\n")
  end

  def cookie_header_for(name)
    set_cookie_headers.find { |header| header.match?(/\A#{Regexp.escape(name)}=/) }.to_s
  end

  def assert_expired_cookie!(set_cookie)
    expires_value = cookie_attribute(set_cookie, "expires")
    assert expires_value.present?, "Expected expires attribute to be present"
    assert Time.httpdate(expires_value) < Time.now, "Expected cookie to expire in the past"
  end

  def cookie_attribute(set_cookie, name)
    match = set_cookie.match(/#{name}=([^;]+)/i)
    match&.captures&.first
  end
end
