require "test_helper"

class CorsCredentialsTest < ActionDispatch::IntegrationTest
  test "preflight from allowed origin returns allow-origin and credentials" do
    origin = "http://app.lvh.me:5173"
    headers = {
      "Origin" => origin,
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "Content-Type, X-CSRF-Token, Authorization, X-Requested-With"
    }

    options "/api/v1/me", headers: headers

    assert_includes [ 200, 204 ], response.status
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
    allow_headers = response.headers["Access-Control-Allow-Headers"].to_s
    assert_includes allow_headers, "Content-Type"
    assert_includes allow_headers, "X-CSRF-Token"
    assert_includes allow_headers, "Authorization"
    assert_includes allow_headers, "X-Requested-With"
  end

  test "request from disallowed origin omits allow-origin" do
    get "/api/v1/health", headers: { "Origin" => "http://evil.com" }

    assert_nil response.headers["Access-Control-Allow-Origin"]
  end
end
