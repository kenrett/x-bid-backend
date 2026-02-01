require "test_helper"

class CorsCredentialsTest < ActionDispatch::IntegrationTest
  ALLOWED_ORIGINS = %w[
    https://biddersweet.app
    https://afterdark.biddersweet.app
    https://marketplace.biddersweet.app
    http://localhost:5173
    http://afterdark.localhost:5173
    http://marketplace.localhost:5173
  ].freeze

  test "api preflight returns allow-origin and credentials for every allowed origin" do
    requested_headers = "content-type, x-csrf-token, authorization, x-request-id, x-storefront-key, sentry-trace, baggage"

    ALLOWED_ORIGINS.each do |origin|
      options "/api/v1/login",
        headers: {
          "Origin" => origin,
          "Access-Control-Request-Method" => "POST",
          "Access-Control-Request-Headers" => requested_headers
        }

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
  end

  test "cable preflight returns allow-origin and credentials for every allowed origin" do
    ALLOWED_ORIGINS.each do |origin|
      options "/cable",
        headers: {
          "Origin" => origin,
          "Access-Control-Request-Method" => "GET"
        }

      assert_includes [ 200, 204 ], response.status
      assert_equal origin, response.headers["Access-Control-Allow-Origin"]
      assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
      assert_includes response.headers["Access-Control-Allow-Methods"].to_s, "GET"
    end
  end

  test "preflight from disallowed origin omits cors headers" do
    options "/api/v1/login",
      headers: {
        "Origin" => "http://evil.example",
        "Access-Control-Request-Method" => "POST"
      }

    assert_includes [ 200, 204 ], response.status
    assert_nil response.headers["Access-Control-Allow-Origin"]
    assert_nil response.headers["Access-Control-Allow-Credentials"]
  end
end
