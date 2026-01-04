require "test_helper"

class ErrorResponseContractTest < ActionDispatch::IntegrationTest
  test "missing required params returns 400 with canonical error shape" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)

    post "/api/v1/me/wins/123/claim", headers: auth_headers_for(user)

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert body.key?("error"), "Expected top-level error key"
    assert_equal "bad_request", body.dig("error", "code").to_s
    assert body.dig("error", "message").to_s.present?
  end

  test "validation errors return 422 with canonical error shape and field_errors" do
    post "/api/v1/signup", params: { user: { email_address: "invalid_signup@example.com" } }

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "validation_error", body.dig("error", "code").to_s
    assert body.dig("error", "message").to_s.present?
    assert body.dig("error", "field_errors").is_a?(Hash), "Expected field_errors hash"
  end

  test "unauthorized returns 401 with canonical error shape" do
    get "/api/v1/wallet"

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert body.key?("error"), "Expected top-level error key"
    assert body.dig("error", "code").to_s.present?
    assert body.dig("error", "message").to_s.present?
  end

  test "malformed JSON returns 400 with canonical error shape" do
    post "/api/v1/signup",
         params: "{ invalid json",
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "bad_request", body.dig("error", "code").to_s
    assert_equal "Malformed JSON", body.dig("error", "message").to_s
  end
end
