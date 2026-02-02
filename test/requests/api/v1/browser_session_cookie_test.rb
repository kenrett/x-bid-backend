require "test_helper"

class BrowserSessionCookieTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Cookie User",
      email_address: "browser-cookie@example.com",
      password: "password",
      bid_credits: 0
    )
  end

  test "login sets browser session cookie" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      host! "api.lvh.me"
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_includes set_cookie, "bs_session_id="
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_match(/path=\//i, set_cookie)
    assert_match(/domain=\.lvh\.me/i, set_cookie)
  end

  test "login sets browser session cookie with expected flags in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_includes set_cookie, "bs_session_id="
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=none/i, set_cookie)
    assert_match(/path=\//i, set_cookie)
    assert_match(/domain=\.biddersweet\.app/i, set_cookie)
    assert_match(/secure/i, set_cookie)
  end

  test "logout clears browser session cookie" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      host! "api.lvh.me"
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
      assert_response :success
      login_body = JSON.parse(response.body)

      SessionEventBroadcaster.stub(:session_invalidated, nil) do
        delete "/api/v1/logout", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }
      end
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_match(/bs_session_id=;?/i, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/path=\//i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert_expired_cookie!(set_cookie)
  end

  test "logout clears browser session cookie with production domain and path" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
      assert_response :success
      login_body = JSON.parse(response.body)

      SessionEventBroadcaster.stub(:session_invalidated, nil) do
        delete "/api/v1/logout", headers: { "Authorization" => bearer(login_body.fetch("access_token")) }
      end
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_match(/bs_session_id=;?/i, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/path=\//i, set_cookie)
    assert_match(/domain=\.biddersweet\.app/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=none/i, set_cookie)
    assert_match(/secure/i, set_cookie)
    assert_expired_cookie!(set_cookie)
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
