require "test_helper"
require "json"

class RateLimitingHttpBoundaryTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.reset!
  end

  test "POST /api/v1/login returns 429 with canonical envelope and Retry-After" do
    user = User.create!(name: "User", email_address: "rate_login@example.com", password: "password", bid_credits: 0)
    throttle = Rack::Attack.throttles.fetch("login/email/short")

    throttle.limit.times do
      post "/api/v1/login",
           params: { session: { email_address: user.email_address, password: "wrong" } },
           headers: ip_headers("1.1.1.1")
      assert_response :unauthorized
    end

    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "wrong" } },
         headers: ip_headers("1.1.1.1")
    assert_response :too_many_requests
    assert_rate_limited!(expected_retry_after: throttle.period.to_i)

    travel throttle.period + 1.second do
      post "/api/v1/login",
           params: { session: { email_address: user.email_address, password: "wrong" } },
           headers: ip_headers("1.1.1.1")
      assert_response :unauthorized
    end
  end

  test "POST /api/v1/signup returns 429 with canonical envelope and Retry-After" do
    throttle = Rack::Attack.throttles.fetch("signup/email")

    throttle.limit.times do
      post "/api/v1/signup",
           params: {
             user: {
               name: "Test",
               email_address: "NewUser@example.com",
               password: "short",
               password_confirmation: "mismatch"
             }
           },
           headers: ip_headers("2.2.2.2")
      assert_response :unprocessable_content
    end

    post "/api/v1/signup",
         params: {
           user: {
             name: "Test",
             email_address: "newuser@example.com",
             password: "short",
             password_confirmation: "mismatch"
           }
         },
         headers: ip_headers("2.2.2.2")
    assert_response :too_many_requests
    assert_rate_limited!(expected_retry_after: throttle.period.to_i)
  end

  test "POST /api/v1/auctions/:id/bids returns 429 with canonical envelope and Retry-After" do
    throttle = Rack::Attack.throttles.fetch("bids/ip")

    stub_authentication_and_bids_controller do
      headers = ip_headers("3.3.3.3").merge("HTTP_AUTHORIZATION" => "Bearer token")

      throttle.limit.times do
        post "/api/v1/auctions/1/bids", headers: headers
        assert_response :success
      end

      post "/api/v1/auctions/1/bids", headers: headers
      assert_response :too_many_requests
      assert_rate_limited!(expected_retry_after: throttle.period.to_i)

      travel throttle.period + 1.second do
        post "/api/v1/auctions/1/bids", headers: headers
        assert_response :success
      end
    end
  end

  private

  def assert_rate_limited!(expected_retry_after:)
    body = JSON.parse(response.body)
    assert_equal "rate_limited", body.dig("error", "code").to_s
    assert body.dig("error", "message").to_s.present?
    assert_equal expected_retry_after.to_s, response.headers["Retry-After"].to_s
  end

  def ip_headers(ip)
    { "REMOTE_ADDR" => ip, "X-Forwarded-For" => ip }
  end

  def stub_authentication_and_bids_controller
    original_authenticate = Api::V1::BidsController.instance_method(:authenticate_request!)
    original_require_verified = Api::V1::BidsController.instance_method(:require_verified_email!)
    original_create = Api::V1::BidsController.instance_method(:create)

    Api::V1::BidsController.define_method(:authenticate_request!) { }
    Api::V1::BidsController.define_method(:require_verified_email!) { }
    Api::V1::BidsController.define_method(:create) { head :ok }

    yield
  ensure
    Api::V1::BidsController.define_method(:authenticate_request!, original_authenticate)
    Api::V1::BidsController.define_method(:require_verified_email!, original_require_verified)
    Api::V1::BidsController.define_method(:create, original_create)
  end
end
