require "test_helper"

class CorsCredentialsTest < ActionDispatch::IntegrationTest
  test "preflight from allowed origin includes credentials headers" do
    origin = "http://localhost:5173"

    options "/api/v1/login",
      headers: {
        "Origin" => origin,
        "Access-Control-Request-Method" => "POST"
      }

    assert_includes [ 200, 204 ], response.status
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "cable preflight from allowed origin includes cors headers" do
    origin = "http://marketplace.localhost:5173"

    options "/cable",
      headers: {
        "Origin" => origin,
        "Access-Control-Request-Method" => "GET"
      }

    assert_includes [ 200, 204 ], response.status
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
  end

  test "preflight from production origin includes explicit allowlist headers" do
    origin = "https://biddersweet.app"

    options "/api/v1/login",
      headers: {
        "Origin" => origin,
        "Access-Control-Request-Method" => "POST"
      }

    assert_includes [ 200, 204 ], response.status
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
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
