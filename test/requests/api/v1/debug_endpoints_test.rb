require "test_helper"

class DebugEndpointsTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/diagnostics/auth returns not found by default" do
    get "/api/v1/diagnostics/auth"

    assert_response :not_found
    assert_equal "Not found", response_json["error"]
  end

  test "GET /api/v1/diagnostics/auth returns diagnostics only when enabled" do
    with_env("DIAGNOSTICS_ENABLED" => "true") do
      host! "api.lvh.me"
      get "/api/v1/diagnostics/auth", headers: { "Origin" => "http://app.lvh.me:5173" }
    end

    assert_response :success
    assert_equal "api.lvh.me", response_json["host"]
    assert_equal "http://app.lvh.me:5173", response_json["origin"]
    assert_includes response_json.keys, "origin_allowed"
    assert_includes response_json.keys, "cookie_domain"
    assert_includes response_json.keys, "browser_session_cookie_present"
    assert_includes response_json.keys, "raw_cookie_present"
    assert_includes response_json.keys, "signed_cookie_readable"
  end

  test "GET /api/v1/diagnostics/auth distinguishes raw and signed browser cookie state" do
    with_env("DIAGNOSTICS_ENABLED" => "true") do
      host! "api.lvh.me"
      get "/api/v1/diagnostics/auth", headers: { "Cookie" => "bs_session_id=bogus" }
    end

    assert_response :success
    assert_equal true, response_json["raw_cookie_present"]
    assert_equal false, response_json["signed_cookie_readable"]
  end

  test "GET /api/v1/auth/debug returns not found by default" do
    get "/api/v1/auth/debug"

    assert_response :not_found
    assert_equal "Not found", response_json["error"]
  end

  test "GET /api/v1/auth/debug returns diagnostics only when enabled" do
    with_env("AUTH_DEBUG_ENABLED" => "true") do
      host! "api.lvh.me"
      get "/api/v1/auth/debug", headers: { "Origin" => "http://app.lvh.me:5173" }
    end

    assert_response :success
    assert_equal "api.lvh.me", response_json["host"]
    assert_equal "http://app.lvh.me:5173", response_json["origin"]
    assert_includes response_json.keys, "storefront_key"
    assert_includes response_json.keys, "cookie_header_present"
    assert_includes response_json.keys, "browser_session_cookie_present"
    assert_includes response_json.keys, "raw_cookie_present"
    assert_includes response_json.keys, "signed_cookie_readable"
    assert_includes response_json.keys, "authorization_header_present"
  end

  test "GET /api/v1/auth/debug distinguishes raw and signed browser cookie state" do
    with_env("AUTH_DEBUG_ENABLED" => "true") do
      host! "api.lvh.me"
      get "/api/v1/auth/debug", headers: { "Cookie" => "bs_session_id=bogus" }
    end

    assert_response :success
    assert_equal true, response_json["raw_cookie_present"]
    assert_equal false, response_json["signed_cookie_readable"]
  end

  private

  def response_json
    JSON.parse(response.body)
  end
end
