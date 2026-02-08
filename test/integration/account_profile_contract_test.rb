require "test_helper"

class AccountProfileContractTest < ActionDispatch::IntegrationTest
  include OpenapiContractHelpers

  EXPECTED_ROOT_KEYS = %w[user].freeze
  EXPECTED_USER_KEYS = %w[
    id
    name
    email_address
    email_verified
    email_verified_at
    created_at
    notification_preferences
  ].freeze
  EXPECTED_NOTIFICATION_PREFERENCE_KEYS = User::NOTIFICATION_PREFERENCE_DEFAULTS.keys.map(&:to_s).sort.freeze

  test "GET /api/v1/account returns the canonical account profile envelope" do
    user = create_actor(role: :user)
    headers = auth_headers_for(user)

    get "/api/v1/account", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal EXPECTED_ROOT_KEYS, body.keys
    assert_equal EXPECTED_USER_KEYS.sort, body.fetch("user").keys.sort
    assert_equal EXPECTED_NOTIFICATION_PREFERENCE_KEYS, body.dig("user", "notification_preferences").keys.sort
    assert_openapi_response_schema!(method: :get, path: "/api/v1/account", status: response.status)
  end

  test "PATCH /api/v1/account returns the canonical account profile envelope" do
    user = create_actor(role: :user)
    headers = auth_headers_for(user)

    patch "/api/v1/account", params: { account: { name: "Updated Name" } }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal EXPECTED_ROOT_KEYS, body.keys
    assert_equal EXPECTED_USER_KEYS.sort, body.fetch("user").keys.sort
    assert_equal "Updated Name", body.dig("user", "name")
    assert_equal EXPECTED_NOTIFICATION_PREFERENCE_KEYS, body.dig("user", "notification_preferences").keys.sort
    assert_openapi_response_schema!(method: :patch, path: "/api/v1/account", status: response.status)
  end
end
