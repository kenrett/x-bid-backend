require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "adds baseline headers" do
    get "/api/v1/auctions"

    csp = response.headers["Content-Security-Policy"]

    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Resource-Policy"]
    assert_includes csp, "default-src 'self'"
    assert_match(/script-src 'self' https:\/\/js\.stripe\.com https:\/\/static\.cloudflareinsights\.com 'nonce-[^']+'/, csp)
    assert_match(/script-src-elem 'self' https:\/\/js\.stripe\.com https:\/\/static\.cloudflareinsights\.com 'nonce-[^']+'/, csp)
    assert_includes csp, "connect-src 'self' https://cloudflareinsights.com"
    refute_includes csp, "'unsafe-inline'"
  end

  test "emits HSTS only over SSL in production" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      get "/api/v1/auctions", headers: { "HTTPS" => "on" }
      assert_match(/max-age=/, response.headers["Strict-Transport-Security"])
    end
  end
end
