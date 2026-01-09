require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  test "throttles excessive login attempts" do
    # Ensure Rack::Attack is enabled for this test
    Rack::Attack.enabled = true

    # The login limit is configured as 20 requests per 30 seconds by IP,
    # but the blocklist triggers at 12 failed attempts.
    limit = 12
    ip = "1.2.3.4"

    # Consume the allowed limit
    limit.times do |i|
      post "/api/v1/login",
        params: { email_address: "attacker-#{i}@example.com", password: "wrong" },
        headers: { "REMOTE_ADDR" => ip }

      assert_response :unauthorized, "Request #{i+1} should have been allowed (but failed auth)"
    end

    # The next request should trigger the throttle
    post "/api/v1/login",
      params: { email_address: "attacker@example.com", password: "wrong" },
      headers: { "REMOTE_ADDR" => ip }

    assert_response :too_many_requests
    assert_includes response.body, "Too many failed attempts"
  end
end
