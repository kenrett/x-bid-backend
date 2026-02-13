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

  test "session-authenticated request rejects disallowed origin and logs origin_rejected" do
    user = User.create!(
      name: "Origin Check User",
      email_address: "origin-check@example.com",
      password: "password",
      bid_credits: 0
    )
    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success

    logged = []
    AppLogger.stub(:log, lambda { |event:, level: :info, **context|
      logged << { event: event, level: level, context: context }
      nil
    }) do
      get "/api/v1/me", headers: { "Origin" => "https://rogue.biddersweet.app" }
    end

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "origin_not_allowed", body.dig("error", "details", "reason")

    origin_rejected = logged.find { |item| item[:event] == "origin_rejected" }
    assert origin_rejected, "Expected origin_rejected log entry"
    assert_equal "https://rogue.biddersweet.app", origin_rejected.dig(:context, :origin)
    assert origin_rejected.dig(:context, :host).present?
  end
end
