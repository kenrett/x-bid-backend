require "test_helper"

class MaintenanceOverrideTest < ActionDispatch::IntegrationTest
  include AuthHelpers

  setup do
    MaintenanceSetting.global.update!(enabled: true)
    Rails.cache.delete("maintenance_mode.enabled")
  end

  teardown do
    MaintenanceSetting.global.update!(enabled: false)
    Rails.cache.delete("maintenance_mode.enabled")
  end

  test "admin bypasses maintenance on auctions index" do
    admin = create_actor(role: :admin)
    get "/api/v1/auctions", headers: auth_headers_for(admin)
    assert_response :success
  end

  test "non-admin sees maintenance on auctions index" do
    user = create_actor(role: :user)
    get "/api/v1/auctions", headers: auth_headers_for(user)
    assert_response :service_unavailable
  end
end
