require "test_helper"

class AuthenticationFailuresTest < ActionDispatch::IntegrationTest
  test "missing authorization header returns missing_authorization_header and logs context" do
    logged = []
    AppLogger.stub(:log, lambda { |event:, level: :info, **context|
      logged << { event: event, level: level, context: context }
      nil
    }) do
      get "/api/v1/me"
    end

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "missing_authorization_header", body.dig("error", "details", "reason")
    assert body.dig("error", "details", "request_id").present?

    entry = logged.find { |item| item[:event] == "auth.failure" }
    assert entry, "Expected auth.failure log entry"
    context = entry[:context]
    assert_equal "me#show", context[:controller_action]
    assert_equal "GET", context[:method]
    assert_equal "/api/v1/me", context[:path]
    assert_equal false, context[:authorization_present]
    assert_equal false, context[:cookie_present]
    assert context[:request_id].present?
  end

  test "missing cookie returns missing_session_cookie" do
    get "/api/v1/me", headers: { "Cookie" => "other_cookie=1" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "missing_session_cookie", body.dig("error", "details", "reason")
  end
end
