require "test_helper"

class CorsSubdomainAuthCompatibilityTest < ActionDispatch::IntegrationTest
  BIDDERSWEET_ORIGINS = %w[
    https://biddersweet.app
    https://afterdark.biddersweet.app
    https://marketplace.biddersweet.app
    https://account.biddersweet.app
  ].freeze

  test "CORS preflight allows biddersweet subdomains and X-Storefront-Key header" do
    BIDDERSWEET_ORIGINS.each do |origin|
      options "/api/v1/login", headers: preflight_headers(origin: origin, requested_headers: "Authorization, Content-Type, X-Storefront-Key")

      assert_includes [ 200, 204 ], response.status
      assert_equal origin, response.headers["Access-Control-Allow-Origin"]
      assert response.headers["Access-Control-Allow-Methods"].to_s.include?("POST")
      assert response.headers["Access-Control-Allow-Headers"].to_s.downcase.include?("x-storefront-key")
    end
  end

  test "auth endpoints accept X-Storefront-Key header" do
    user = User.create!(name: "CORS User", email_address: "cors_user@example.com", password: "password", bid_credits: 0)

    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "password" } },
         headers: {
           "Origin" => "https://afterdark.biddersweet.app",
           "X-Storefront-Key" => "afterdark"
         }

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
