require "test_helper"

class AdminUsersApiTest < ActionDispatch::IntegrationTest
  def setup
    @superadmin = create_actor(role: :superadmin)
    @other_superadmin = create_actor(role: :superadmin)
    @admin = create_actor(role: :admin)
    @user = create_actor(role: :user)
  end

  test "GET /api/v1/admin/users lists manageable users by actor role" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/users", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      users = body["users"] || body["admin_users"] || body["adminUsers"] || body
      assert_kind_of Array, users
      ids = users.map { |u| u["id"] }
      assert_includes ids, @user.id

      if role == :admin
        assert_not_includes ids, @admin.id
        assert_not_includes ids, @superadmin.id
        assert_not_includes ids, @other_superadmin.id
      else
        assert_includes ids, @admin.id
        assert_includes ids, @superadmin.id
        assert_includes ids, @other_superadmin.id
      end

      sample = users.find { |u| u["id"] == @user.id } || users.first
      assert sample.key?("status")
      assert sample.key?("email_verified")
      assert sample.key?("email_verified_at")
    end
  end

  test "POST /api/v1/admin/users/:id/grant_admin enforces role matrix and updates role" do
    target = create_actor(role: :user)

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/users/#{target.id}/grant_admin", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "admin", parsed_user(JSON.parse(response.body))["role"]
        assert_equal "admin", target.reload.role
      else
        assert_equal "user", target.reload.role
      end
    end
  end

  test "POST /api/v1/admin/users/:id/revoke_admin enforces role matrix and updates role" do
    target = create_actor(role: :admin)

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/users/#{target.id}/revoke_admin", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "user", parsed_user(JSON.parse(response.body))["role"]
        assert_equal "user", target.reload.role
      else
        assert_equal "admin", target.reload.role
      end
    end
  end

  test "POST /api/v1/admin/users/:id/grant_superadmin enforces role matrix and updates role" do
    target = create_actor(role: :admin)

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/users/#{target.id}/grant_superadmin", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "superadmin", parsed_user(JSON.parse(response.body))["role"]
        assert_equal "superadmin", target.reload.role
      else
        assert_equal "admin", target.reload.role
      end
    end
  end

  test "POST /api/v1/admin/users/:id/revoke_superadmin enforces role matrix and updates role" do
    target = @other_superadmin

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/users/#{target.id}/revoke_superadmin", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "admin", parsed_user(JSON.parse(response.body))["role"]
        assert_equal "admin", target.reload.role
      else
        assert_equal "superadmin", target.reload.role
      end
    end
  end

  test "role changes revoke target user sessions" do
    target = create_actor(role: :user)
    target_session = SessionToken.create!(
      user: target,
      token_digest: SessionToken.digest("role-change"),
      expires_at: 1.hour.from_now
    )
    target_headers = auth_headers_for_session(target, target_session)

    post "/api/v1/admin/users/#{target.id}/grant_admin", headers: auth_headers_for(@superadmin)
    assert_response :success
    assert target_session.reload.revoked_at.present?

    get "/api/v1/me", headers: target_headers
    assert_response :unauthorized
  end

  test "PATCH role change revokes target user sessions" do
    target = create_actor(role: :user)
    target_session = SessionToken.create!(
      user: target,
      token_digest: SessionToken.digest("patch-role-change"),
      expires_at: 1.hour.from_now
    )
    target_headers = auth_headers_for_session(target, target_session)

    patch "/api/v1/admin/users/#{target.id}",
          params: { user: { role: "admin" } },
          headers: auth_headers_for(@superadmin)
    assert_response :success
    assert_equal "admin", target.reload.role
    assert target_session.reload.revoked_at.present?

    get "/api/v1/me", headers: target_headers
    assert_response :unauthorized
  end

  test "POST /api/v1/admin/users/:id/ban allows admin moderation of role=user and is idempotent" do
    target = create_actor(role: :user)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/admin/users/#{target.id}/ban", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "disabled", parsed_user(JSON.parse(response.body))["status"]
        assert_equal "disabled", target.reload.status

        post "/api/v1/admin/users/#{target.id}/ban", headers: headers
        assert_response :success
        assert_equal "disabled", parsed_user(JSON.parse(response.body))["status"]
        assert_equal "disabled", target.reload.status
      else
        assert_equal "active", target.reload.status
      end
    end
  end

  test "PATCH /api/v1/admin/users/:id allows moderation fields and audits updates" do
    target = create_actor(role: :user)
    params = { user: { status: "disabled", email_verified: true } }

    each_role_case(required_role: :admin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        patch "/api/v1/admin/users/#{target.id}", params: params, headers: headers
      end

      assert_response expected_status

      if success
        payload = parsed_user(JSON.parse(response.body))
        assert_equal "disabled", payload["status"]
        assert_equal true, payload["email_verified"]
        assert payload["email_verified_at"].present?
        assert_equal "disabled", target.reload.status
        assert target.email_verified?

        log = AuditLog.where(action: "user.update").order(created_at: :desc).first
        assert_equal "user.update", log.action
        assert_equal actor.id, log.actor_id
        assert_equal target.id, log.target_id
      else
        assert_equal "active", target.reload.status
        assert_not target.email_verified?
      end
    end
  end

  test "admin cannot moderate non-user accounts" do
    admin = create_actor(role: :admin)
    target = create_actor(role: :admin)

    patch "/api/v1/admin/users/#{target.id}",
          params: { user: { status: "disabled" } },
          headers: auth_headers_for(admin)

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).dig("error", "code")
    assert_equal "active", target.reload.status
  end

  test "admin cannot update roles via PATCH" do
    admin = create_actor(role: :admin)
    target = create_actor(role: :user)

    patch "/api/v1/admin/users/#{target.id}",
          params: { user: { role: "admin" } },
          headers: auth_headers_for(admin)

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body).dig("error", "code")
    assert_equal "user", target.reload.role
  end

  test "PATCH maps banned and suspended moderation states to disabled" do
    superadmin_headers = auth_headers_for(create_actor(role: :superadmin))
    target = create_actor(role: :user)

    patch "/api/v1/admin/users/#{target.id}",
          params: { user: { status: "banned" } },
          headers: superadmin_headers
    assert_response :success
    assert_equal "disabled", target.reload.status

    patch "/api/v1/admin/users/#{target.id}",
          params: { user: { status: "suspended" } },
          headers: superadmin_headers
    assert_response :success
    assert_equal "disabled", target.reload.status
  end

  private

  def parsed_user(body)
    body["admin_user"] ||
      body["adminUser"] ||
      body.values.find { |v| v.is_a?(Hash) && (v.key?("status") || v.key?("role") || v.key?("email_address") || v.key?("emailAddress")) } ||
      body ||
      {}
  end

  def auth_headers_for_session(user, session_token, exp: 1.hour.from_now.to_i)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    token = encode_jwt(payload)
    { "Authorization" => "Bearer #{token}" }
  end
end
