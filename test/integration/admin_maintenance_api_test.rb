require "test_helper"

class AdminMaintenanceApiTest < ActionDispatch::IntegrationTest
  def setup
    MaintenanceSetting.global.update!(enabled: false)
    Rails.cache.write("maintenance_mode.enabled", false)
  end

  test "GET /api/v1/admin/maintenance enforces role matrix" do
    each_role_case(required_role: :superadmin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/maintenance", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal false, body.dig("maintenance", "enabled")
      assert body.dig("maintenance", "updated_at").present?
    end
  end

  test "POST /api/v1/admin/maintenance enforces role matrix and audits changes" do
    each_role_case(required_role: :superadmin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        post "/api/v1/admin/maintenance", params: { enabled: true }, headers: headers
      end

      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal true, body.dig("maintenance", "enabled")
        assert_equal true, MaintenanceSetting.global.reload.enabled

        log = AuditLog.where(action: "maintenance.update").order(created_at: :desc).first
        assert_equal "maintenance.update", log.action
        assert_equal actor.id, log.actor_id
        assert_equal true, log.payload["enabled"]
      else
        assert_equal false, MaintenanceSetting.global.reload.enabled
      end
    end
  end
end
