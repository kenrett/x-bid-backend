require "test_helper"

class LegacyMeAccountEndpointsTest < ActionDispatch::IntegrationTest
  test "legacy /api/v1/me/account endpoints return JSON 404" do
    get "/api/v1/me/account/profile"
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body["error_code"]

    post "/api/v1/me/account/password", params: { current_password: "x", new_password: "y" }
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body["error_code"]

    delete "/api/v1/me/account"
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body["error_code"]
  end
end
