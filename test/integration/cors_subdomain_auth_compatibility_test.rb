require "test_helper"

class CorsSubdomainAuthCompatibilityTest < ActionDispatch::IntegrationTest
  BIDDERSWEET_ORIGINS = %w[
    https://biddersweet.app
    https://afterdark.biddersweet.app
    https://marketplace.biddersweet.app
  ].freeze

  test "CORS preflight allows biddersweet subdomains and credentialed headers" do
    BIDDERSWEET_ORIGINS.each do |origin|
      options "/api/v1/login", headers: preflight_headers(origin: origin, requested_headers: "Authorization, Content-Type, X-Requested-With, X-CSRF-Token")

      assert_includes [ 200, 204 ], response.status
      assert_equal origin, response.headers["Access-Control-Allow-Origin"]
      assert response.headers["Access-Control-Allow-Methods"].to_s.include?("POST")
      allowed = response.headers["Access-Control-Allow-Headers"].to_s.downcase
      assert allowed.include?("x-csrf-token")
      assert allowed.include?("x-requested-with")
    end
  end

  test "auth endpoints reflect allow-origin for biddersweet origins" do
    user = User.create!(name: "CORS User", email_address: "cors_user@example.com", password: "password", bid_credits: 0)

    csrf = csrf_headers(origin: "https://afterdark.biddersweet.app")
    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "password" } },
         headers: csrf

    assert_response :success
    assert_equal "https://afterdark.biddersweet.app", response.headers["Access-Control-Allow-Origin"]
  end

  private

  def preflight_headers(origin:, requested_headers:)
    {
      "Origin" => origin,
      "Access-Control-Request-Method" => "POST",
      "Access-Control-Request-Headers" => requested_headers
    }
  end
end
