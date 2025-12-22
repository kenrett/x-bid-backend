require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "adds baseline headers" do
    get "/up"

    csp = response.headers["Content-Security-Policy"]

    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Resource-Policy"]
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "script-src 'self' https://js.stripe.com https://static.cloudflareinsights.com 'unsafe-inline'"
  end

  test "emits HSTS only over SSL in production" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      get "/up", headers: { "HTTPS" => "on" }
      assert_match(/max-age=/, response.headers["Strict-Transport-Security"])
    end
  end
end
