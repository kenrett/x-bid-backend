require "test_helper"
require "json"

class OpenapiAdminRefundDocsTest < ActionDispatch::IntegrationTest
  test "OpenAPI includes admin refund endpoint with request/response schemas" do
    openapi_path = Rails.root.join("docs", "api", "openapi.json")
    assert File.exist?(openapi_path), "Missing OpenAPI spec at #{openapi_path} (run `bin/rails openapi:generate`)"
    spec = JSON.parse(File.read(openapi_path))

    refund = spec.dig("paths", "/api/v1/admin/payments/{id}/refund", "post")
    assert refund, "Expected OpenAPI to include POST /api/v1/admin/payments/{id}/refund"

    request_body = resolve(spec, refund["requestBody"])
    request_schema = resolve(spec, request_body.dig("content", "application/json", "schema"))
    assert_equal "object", request_schema["type"]

    required = Array(request_schema["required"])
    refute_includes required, "amount_cents"

    response_200 = resolve(spec, refund.dig("responses", "200"))
    response_schema = resolve(spec, response_200.dig("content", "application/json", "schema"))
    properties = response_schema.fetch("properties", {})
    assert_includes properties.keys, "refund_id"
    assert_includes properties.keys, "stripe_payment_intent_id"
    assert_includes properties.keys, "stripe_checkout_session_id"
  end

  private

  def resolve(spec, obj)
    current = obj
    while current.is_a?(Hash) && current["$ref"].present?
      current = resolve_ref(spec, current["$ref"])
    end
    current || {}
  end

  def resolve_ref(spec, ref)
    raise ArgumentError, "Unsupported ref #{ref.inspect}" unless ref&.start_with?("#/")

    ref.split("/").drop(1).reduce(spec) { |acc, part| acc.fetch(part) }
  end
end
