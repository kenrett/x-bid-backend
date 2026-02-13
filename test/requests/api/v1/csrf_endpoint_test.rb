require "test_helper"

class CsrfEndpointTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/csrf returns token and sets cookie" do
    host! "api.lvh.me"
    get "/api/v1/csrf", headers: { "Origin" => "http://app.lvh.me:5173" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["csrf_token"].is_a?(String)
    set_cookie = set_cookie_header
    assert_includes set_cookie, "csrf_token"
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
  end

  test "GET /api/v1/csrf sets Secure in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      host! "api.biddersweet.app"
      https!
      get "/api/v1/csrf", headers: { "Origin" => "https://afterdark.biddersweet.app" }
    end

    assert_response :success
    set_cookie = set_cookie_header
    assert_includes set_cookie, "csrf_token"
    assert_match(/httponly/i, set_cookie)
    assert_match(/secure/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    refute_match(/domain=/i, set_cookie)
  end

  private

  def set_cookie_header
    header = response.headers["Set-Cookie"]
    return header.join("\n") if header.is_a?(Array)

    header.to_s
  end
end
