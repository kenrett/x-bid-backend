require "test_helper"

class AdminSessionsApiTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/admin/sessions/revoke_all enforces role matrix" do
    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/sessions/revoke_all", params: { reason: "drill_#{role}" }, headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal "revoked", body["status"]
      assert body["sessions_revoked"].is_a?(Integer)
      assert body["revoked_at"].present?
    end
  end

  test "global revoke invalidates existing browser cookie sessions" do
    user = User.create!(
      name: "Cookie User",
      email_address: "global-revoke-cookie@example.com",
      password: "password",
      role: :user,
      bid_credits: 0
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    user_session_id = JSON.parse(response.body).fetch("session_token_id")

    get "/api/v1/logged_in"
    assert_response :success
    assert_equal true, JSON.parse(response.body)["logged_in"]

    superadmin = create_actor(role: :superadmin)
    admin_client = open_session
    admin_client.post(
      "/api/v1/admin/sessions/revoke_all",
      params: { reason: "suspected_cookie_replay" },
      headers: auth_headers_for(superadmin)
    )
    assert_equal 200, admin_client.response.status

    get "/api/v1/logged_in"
    assert_response :unauthorized
    assert_equal "invalid_session", JSON.parse(response.body).dig("error", "code")
    assert SessionToken.find(user_session_id).revoked_at.present?
  end

  test "global revoke writes an audit trail with actor and revoked count" do
    superadmin = create_actor(role: :superadmin)
    user = create_actor(role: :user)
    SessionToken.create!(user: user, token_digest: SessionToken.digest("audit-revoke-user"), expires_at: 1.hour.from_now)

    post "/api/v1/admin/sessions/revoke_all",
         params: { reason: "suspected_subdomain_takeover", rotate_signing_secrets: true },
         headers: auth_headers_for(superadmin)

    assert_response :success
    log = AuditLog.where(action: "auth.sessions.global_revoke").order(created_at: :desc).first
    assert log.present?, "Expected auth.sessions.global_revoke audit log"
    assert_equal superadmin.id, log.actor_id
    assert_equal "suspected_subdomain_takeover", log.payload["reason"]
    assert_equal true, log.payload["rotate_signing_secrets"]
    assert log.payload["revoked_at"].present?
    assert_operator log.payload["revoked_count"].to_i, :>=, 1
  end
end
