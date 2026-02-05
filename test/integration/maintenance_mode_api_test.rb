require "test_helper"
require "jwt"

class MaintenanceModeApiTest < ActionDispatch::IntegrationTest
  def setup
    MaintenanceSetting.global.update!(enabled: false)
    Rails.cache.write("maintenance_mode.enabled", false)
    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
    @session_token = SessionToken.create!(user: @admin, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
  end

  test "public flag returns maintenance status without auth" do
    get "/api/v1/maintenance"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body.dig("maintenance", "enabled")
  end

  test "blocks non-admin requests with 503 when maintenance is enabled" do
    MaintenanceSetting.global.update!(enabled: true)
    Rails.cache.write("maintenance_mode.enabled", true)

    get "/api/v1/auctions"
    assert_response :service_unavailable
    body = JSON.parse(response.body)
    assert_equal "maintenance_mode", body.dig("error", "code").to_s
    assert_equal "Maintenance in progress", body.dig("error", "message")
  end

  test "allows admin requests during maintenance" do
    MaintenanceSetting.global.update!(enabled: true)
    Rails.cache.write("maintenance_mode.enabled", true)

    get "/api/v1/auctions", headers: auth_headers
    assert_response :success
  end

  private

  def auth_headers
    payload = { user_id: @admin.id, session_token_id: @session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)
    { "Authorization" => "Bearer #{token}" }
  end
end
