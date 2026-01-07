require "test_helper"
require "json"

class OpenapiLoggedInStatusSchemaTest < ActionDispatch::IntegrationTest
  test "OpenAPI LoggedInStatus matches runtime keys and is used by GET /api/v1/logged_in" do
    spec = JSON.parse(File.read(Rails.root.join("docs/api/openapi.json")))

    status_schema = spec.dig("components", "schemas", "LoggedInStatus")
    assert status_schema.is_a?(Hash), "Expected OpenAPI spec to include components.schemas.LoggedInStatus"

    properties = status_schema.fetch("properties")
    required = status_schema.fetch("required")

    expected_keys = %w[
      logged_in
      user
      is_admin
      is_superuser
      redirect_path
      session_token_id
      session_expires_at
      seconds_remaining
      session
    ]

    assert_equal expected_keys.sort, properties.keys.sort
    assert_equal expected_keys.sort, required.sort

    operation = spec.dig("paths", "/api/v1/logged_in", "get")
    assert operation.is_a?(Hash), "Expected OpenAPI to include GET /api/v1/logged_in"

    response_200 = resolve_ref(spec, operation.dig("responses", "200")) || {}
    schema_200 = response_200.dig("content", "application/json", "schema")
    schema_200 = resolve_ref(spec, schema_200) || {}

    assert_equal({ "$ref" => "#/components/schemas/LoggedInStatus" }, schema_200)
  end

  def resolve_ref(spec, node)
    return node unless node.is_a?(Hash) && node.key?("$ref")

    ref = node.fetch("$ref")
    return node unless ref.start_with?("#/")

    pointer = ref.delete_prefix("#/").split("/")
    pointer.reduce(spec) { |acc, token| acc.fetch(token) }
  end
end
