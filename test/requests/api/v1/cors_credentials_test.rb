require "test_helper"

class CorsCredentialsTest < ActionDispatch::IntegrationTest
  test "preflight from allowed origin returns allow-origin and credentials" do
    origin = "http://localhost:5173"
    headers = {
      "Origin" => origin,
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "content-type, x-csrf-token, authorization, x-request-id, x-storefront-key, sentry-trace, baggage"
    }

    options "/api/v1/me", headers: headers

    assert_includes [ 200, 204 ], response.status
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
    allow_headers = response.headers["Access-Control-Allow-Headers"].to_s
    assert_includes allow_headers, "content-type"
    assert_includes allow_headers, "x-csrf-token"
    assert_includes allow_headers, "authorization"
    assert_includes allow_headers, "x-request-id"
    assert_includes allow_headers, "x-storefront-key"
    assert_includes allow_headers, "sentry-trace"
    assert_includes allow_headers, "baggage"
  end

  test "request from disallowed origin omits allow-origin" do
    get "/api/v1/health", headers: { "Origin" => "http://evil.com" }

    assert_nil response.headers["Access-Control-Allow-Origin"]
  end
end
