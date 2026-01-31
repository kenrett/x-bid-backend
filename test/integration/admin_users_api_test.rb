require "test_helper"

class AdminUsersApiTest < ActionDispatch::IntegrationTest
  def setup
    @superadmin = create_actor(role: :superadmin)
    @other_superadmin = create_actor(role: :superadmin)
    @admin = create_actor(role: :admin)
    @user = create_actor(role: :user)
  end

  test "GET /api/v1/admin/users enforces role matrix" do
    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/users", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      users = body["users"] || body["admin_users"] || body["adminUsers"] || body
      assert_kind_of Array, users
      ids = users.map { |u| u["id"] }
      assert_includes ids, @superadmin.id
      assert_includes ids, @admin.id
      assert_not_includes ids, @user.id
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

  test "POST /api/v1/admin/users/:id/ban enforces role matrix and is idempotent" do
    target = create_actor(role: :user)

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
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

  test "PATCH /api/v1/admin/users/:id enforces role matrix and audits updates" do
    target = create_actor(role: :admin)
    params = { user: { name: "Renamed Admin" } }

    each_role_case(required_role: :superadmin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        patch "/api/v1/admin/users/#{target.id}", params: params, headers: headers
      end

      assert_response expected_status

      if success
        assert_equal "Renamed Admin", parsed_user(JSON.parse(response.body))["name"]
        assert_equal "Renamed Admin", target.reload.name

        log = AuditLog.where(action: "user.update").order(created_at: :desc).first
        assert_equal "user.update", log.action
        assert_equal actor.id, log.actor_id
        assert_equal target.id, log.target_id
      else
        assert_not_equal "Renamed Admin", target.reload.name
      end
    end
  end

  private

  def parsed_user(body)
    body["admin_user"] ||
      body["adminUser"] ||
      body.values.find { |v| v.is_a?(Hash) && (v.key?("status") || v.key?("role") || v.key?("email_address") || v.key?("emailAddress")) } ||
      body ||
      {}
  end
end
