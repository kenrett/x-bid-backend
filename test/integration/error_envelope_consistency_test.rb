require "test_helper"

class ErrorEnvelopeConsistencyTest < ActionDispatch::IntegrationTest
  test "superadmin-only endpoints return render_error envelope" do
    admin = create_actor(role: :admin)

    get "/api/v1/admin/maintenance", headers: auth_headers_for(admin)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error_code"].to_s
    assert_equal "Superadmin privileges required", body["message"]
  end
end
