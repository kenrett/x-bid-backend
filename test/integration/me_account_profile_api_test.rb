require "test_helper"

class MeAccountProfileApiTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/me/account/profile returns AccountProfile shape" do
    user = User.create!(name: "User", email_address: "me_profile@example.com", password: "password", bid_credits: 0)

    get "/api/v1/me/account/profile", headers: auth_headers_for(user)
    assert_response :success

    body = JSON.parse(response.body)
    assert body["user"].is_a?(Hash)
    assert_equal user.id, body.dig("user", "id")
    assert_equal user.email_address, body.dig("user", "email_address")
    assert_includes body.dig("user", "notification_preferences").keys, "bidding_alerts"
  end
end
