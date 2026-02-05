require "test_helper"
require "jwt"

class MaintenanceModeMatrixTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.write("maintenance_mode.enabled", false)
    MaintenanceSetting.global.update!(enabled: false)

    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
    @superadmin = User.create!(name: "Super", email_address: "super@example.com", password: "password", role: :superadmin, bid_credits: 0)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", role: :user, bid_credits: 0)

    @admin_session = SessionToken.create!(user: @admin, token_digest: SessionToken.digest("raw_admin"), expires_at: 1.hour.from_now)
    @superadmin_session = SessionToken.create!(user: @superadmin, token_digest: SessionToken.digest("raw_super"), expires_at: 1.hour.from_now)
    @user_session = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw_user"), expires_at: 1.hour.from_now)
  end

  test "maintenance blocks anon and user but allows admin/superadmin on auctions index" do
    enable_maintenance

    get "/api/v1/auctions"
    assert_response :service_unavailable

    get "/api/v1/auctions", headers: auth_headers(@user, @user_session)
    assert_response :service_unavailable

    get "/api/v1/auctions", headers: auth_headers(@admin, @admin_session)
    assert_response :success

    get "/api/v1/auctions", headers: auth_headers(@superadmin, @superadmin_session)
    assert_response :success
  end

  test "public maintenance flag is always accessible" do
    enable_maintenance

    get "/api/v1/maintenance"
    assert_response :success
  end

  private

  def enable_maintenance
    MaintenanceSetting.global.update!(enabled: true)
    Rails.cache.write("maintenance_mode.enabled", true)
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)
    { "Authorization" => "Bearer #{token}" }
  end
end
