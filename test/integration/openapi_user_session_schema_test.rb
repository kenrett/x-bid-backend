require "test_helper"
require "json"

class OpenapiUserSessionSchemaTest < ActionDispatch::IntegrationTest
  test "OpenAPI UserSession marks bearer tokens as optional and omits legacy token" do
    spec = JSON.parse(File.read(Rails.root.join("docs/api/openapi.json")))
    user_session = spec.dig("components", "schemas", "UserSession")
    assert user_session.is_a?(Hash), "Expected OpenAPI spec to include components.schemas.UserSession"

    properties = user_session.fetch("properties")
    assert properties.key?("access_token"), "Expected UserSession.properties.access_token"
    refute properties.key?("token"), "Expected UserSession.properties.token to be absent"

    required = user_session.fetch("required")
    assert_includes required, "session_token_id"
    assert_includes required, "user"
    refute_includes required, "access_token"
    refute_includes required, "refresh_token"
    refute_includes required, "token"
  end
end
