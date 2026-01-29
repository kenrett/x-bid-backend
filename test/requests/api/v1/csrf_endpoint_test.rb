require "test_helper"

class CsrfEndpointTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/csrf returns token and sets cookie" do
    host! "api.lvh.me"
    get "/api/v1/csrf", headers: { "Origin" => "http://app.lvh.me:5173" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["csrf_token"].is_a?(String)
    assert_includes response.headers["Set-Cookie"].to_s, "csrf_token"
  end
end
