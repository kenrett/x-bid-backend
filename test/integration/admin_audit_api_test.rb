require "test_helper"

class AdminAuditApiTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/admin/audit enforces role matrix and creates logs for admins" do
    target = create_actor(role: :admin)

    params = {
      audit: {
        action: "custom.test",
        target_type: "User",
        target_id: target.id,
        payload: { example: true }
      }
    }

    each_role_case(required_role: :admin, success_status: 201) do |role:, actor:, headers:, expected_status:, success:|
      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        post "/api/v1/admin/audit", params: params, headers: headers, as: :json
      end

      assert_response expected_status

      next unless success

      body = JSON.parse(response.body)
      assert_equal "ok", body["status"]

      log = AuditLog.where(action: "custom.test").order(created_at: :desc).first
      assert_equal "custom.test", log.action
      assert_equal actor.id, log.actor_id
      assert_equal "User", log.target_type
      assert_equal target.id, log.target_id
      assert_equal true, log.payload["example"]
    end
  end
end
