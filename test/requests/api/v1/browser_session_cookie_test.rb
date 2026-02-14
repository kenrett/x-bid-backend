require "test_helper"

class BrowserSessionCookieTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(
      name: "Cookie User",
      email_address: "browser-cookie@example.com",
      password: "password",
      bid_credits: 0
    )
  end

  test "login sets host-only browser session cookie with hardened flags" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("development")) do
      host! "api.lvh.me"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success

    session_cookie = cookie_header_for("__Host-bs_session_id")
    assert_includes session_cookie, "__Host-bs_session_id="
    assert_match(/httponly/i, session_cookie)
    assert_match(/samesite=lax/i, session_cookie)
    assert_match(/path=\//i, session_cookie)
    refute_match(/domain=/i, session_cookie)
  end

  test "login clears legacy shared-domain browser session cookie during migration" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    end

    assert_response :success

    session_cookie = cookie_header_for("__Host-bs_session_id")
    assert_includes session_cookie, "__Host-bs_session_id="
    assert_match(/httponly/i, session_cookie)
    assert_match(/samesite=lax/i, session_cookie)
    assert_match(/path=\//i, session_cookie)
    assert_match(/secure/i, session_cookie)
    refute_match(/domain=/i, session_cookie)

    legacy_cookie = cookie_headers_for("bs_session_id").find { |header| header.match?(/domain=\.biddersweet\.app/i) }
    assert legacy_cookie.present?, "Expected legacy cookie clear with Domain=.biddersweet.app"
    assert_match(/bs_session_id=;?/i, legacy_cookie)
    assert_match(/expires=/i, legacy_cookie)
    assert_match(/secure/i, legacy_cookie)
    assert_expired_cookie!(legacy_cookie)
  end

  test "login keeps SameSite=Lax even when none is requested" do
    with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => "true") do
      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        host! "api.biddersweet.app"
        https!
        post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
      end
    end

    assert_response :success
    session_cookie = cookie_header_for("__Host-bs_session_id")
    assert_match(/samesite=lax/i, session_cookie)
    refute_match(/samesite=none/i, session_cookie)
  end

  test "logout clears host-only and legacy browser session cookies" do
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

    session_cookie = cookie_header_for("__Host-bs_session_id")
    assert_match(/__Host-bs_session_id=;?/i, session_cookie)
    assert_match(/expires=/i, session_cookie)
    assert_match(/path=\//i, session_cookie)
    assert_match(/httponly/i, session_cookie)
    assert_match(/samesite=lax/i, session_cookie)
    assert_match(/secure/i, session_cookie)
    refute_match(/domain=/i, session_cookie)
    assert_expired_cookie!(session_cookie)

    legacy_cookie = cookie_headers_for("bs_session_id").find { |header| header.match?(/domain=\.biddersweet\.app/i) }
    assert legacy_cookie.present?, "Expected legacy cookie clear with Domain=.biddersweet.app"
    assert_match(/bs_session_id=;?/i, legacy_cookie)
    assert_match(/expires=/i, legacy_cookie)
    assert_match(/path=\//i, legacy_cookie)
    assert_match(/httponly/i, legacy_cookie)
    assert_match(/samesite=lax/i, legacy_cookie)
    assert_match(/secure/i, legacy_cookie)
    assert_expired_cookie!(legacy_cookie)
  end

  test "cookie expiration is refreshed when sliding session ttl extends" do
    with_session_ttls(idle_minutes: 5, absolute_minutes: 30) do
      t0 = Time.current.change(usec: 0)
      travel_to(t0)
      begin
        post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
        assert_response :success
        initial_cookie = cookie_header_for("__Host-bs_session_id")
        initial_expires = Time.httpdate(cookie_attribute(initial_cookie, "expires"))

        travel_to(t0 + 4.minutes)
        get "/api/v1/logged_in"
        assert_response :success
        refreshed_cookie = cookie_header_for("__Host-bs_session_id")
        refreshed_expires = Time.httpdate(cookie_attribute(refreshed_cookie, "expires"))

        assert_operator refreshed_expires, :>, initial_expires
      ensure
        travel_back
      end
    end
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
    cookie_headers_for(name).first.to_s
  end

  def cookie_headers_for(name)
    set_cookie_headers.select { |header| header.match?(/\A#{Regexp.escape(name)}=/) }
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

  def with_session_ttls(idle_minutes:, absolute_minutes:)
    previous_idle = Rails.configuration.x.session_token_idle_ttl
    previous_legacy = Rails.configuration.x.session_token_ttl
    previous_absolute = Rails.configuration.x.session_token_absolute_ttl

    Rails.configuration.x.session_token_idle_ttl = idle_minutes.minutes
    Rails.configuration.x.session_token_ttl = idle_minutes.minutes
    Rails.configuration.x.session_token_absolute_ttl = absolute_minutes.minutes
    yield
  ensure
    Rails.configuration.x.session_token_idle_ttl = previous_idle
    Rails.configuration.x.session_token_ttl = previous_legacy
    Rails.configuration.x.session_token_absolute_ttl = previous_absolute
  end
end
