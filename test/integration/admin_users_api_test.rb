require "test_helper"
require "jwt"

class AdminUsersApiTest < ActionDispatch::IntegrationTest
  def setup
    @superadmin = User.create!(name: "Super", email_address: "super@example.com", password: "password", role: :superadmin, bid_credits: 0)
    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", role: :user, bid_credits: 0)

    @superadmin_session = SessionToken.create!(user: @superadmin, token_digest: SessionToken.digest("raw-super"), expires_at: 1.hour.from_now)
    @admin_session = SessionToken.create!(user: @admin, token_digest: SessionToken.digest("raw-admin"), expires_at: 1.hour.from_now)
  end

  test "superadmin can ban (disable) a user" do
    post "/api/v1/admin/users/#{@user.id}/ban", headers: auth_headers(user: @superadmin, session: @superadmin_session)

    assert_response :success
    data = parsed_user(JSON.parse(response.body))
    assert_equal "disabled", data["status"]
    assert_equal "disabled", @user.reload.status
  end

  test "ban is idempotent when user already disabled" do
    @user.update!(status: :disabled)

    post "/api/v1/admin/users/#{@user.id}/ban", headers: auth_headers(user: @superadmin, session: @superadmin_session)

    assert_response :success
    data = parsed_user(JSON.parse(response.body))
    assert_equal "disabled", data["status"]
    assert_equal "disabled", @user.reload.status
  end

  test "non-superadmin cannot ban" do
    post "/api/v1/admin/users/#{@user.id}/ban", headers: auth_headers(user: @admin, session: @admin_session)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "Superadmin privileges required", body["error"]
    assert_equal "active", @user.reload.status
  end

  private

  def auth_headers(user:, session:)
    payload = { user_id: user.id, session_token_id: session.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def parsed_user(body)
    body["admin_user"] ||
      body["adminUser"] ||
      body.values.find { |v| v.is_a?(Hash) && v.key?("status") } ||
      {}
  end
end
