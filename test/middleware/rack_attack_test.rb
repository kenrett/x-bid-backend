require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.reset!
  end

  test "throttles login by normalized email and IP" do
    8.times do
      post_login("User@example.com")
      assert_response :unauthorized
    end

    post_login("user@example.com")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many login attempts", expected_retry_after: 10.minutes.to_i)

    post_login("other@example.com")
    assert_response :unauthorized
  end

  test "locks out repeated login attempts by IP after backoff threshold" do
    12.times do |idx|
      post_login("user-#{idx}@example.com", ip: "2.2.2.2")
      assert_response :unauthorized
    end

    post_login("final@example.com", ip: "2.2.2.2")
    assert_response :too_many_requests
    assert_includes response.body, "locked_out"

    post_login("after-lockout@example.com", ip: "2.2.2.2")
    assert_response :too_many_requests
  end

  test "throttles bidding endpoints separately from general traffic" do
    stub_authentication_and_bids_controller do
      50.times do
        post "/api/v1/auctions/1/bids", headers: ip_headers("3.3.3.3").merge("HTTP_AUTHORIZATION" => "Bearer token")
        assert_not_equal 429, response.status
      end

      post "/api/v1/auctions/1/bids", headers: ip_headers("3.3.3.3").merge("HTTP_AUTHORIZATION" => "Bearer token")
      assert_response :too_many_requests
      assert_throttled!(expected_message: "Too many bid attempts", expected_retry_after: 1.minute.to_i)

      post "/api/v1/auctions/1/bids", headers: ip_headers("4.4.4.4").merge("HTTP_AUTHORIZATION" => "Bearer token")
      assert_response :ok
    end
  end

  test "throttles signup by normalized email and IP" do
    6.times do
      post_signup("NewUser@example.com")
      assert_response :unprocessable_content
    end

    post_signup("newuser@example.com")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many signup attempts", expected_retry_after: 1.hour.to_i)

    post_signup("other_signup@example.com")
    assert_response :unprocessable_content
  end

  test "throttles password reset by normalized email" do
    6.times do
      post_password_forgot("ResetUser@example.com")
      assert_response :accepted
    end

    post_password_forgot("resetuser@example.com")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many password attempts", expected_retry_after: 30.minutes.to_i)

    post_password_forgot("other_reset@example.com")
    assert_response :accepted
  end

  test "throttles checkout creation by IP" do
    15.times do
      post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("5.5.5.5")
      assert_not_equal 429, response.status
    end

    post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("5.5.5.5")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many checkout attempts", expected_retry_after: 10.minutes.to_i)

    post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("6.6.6.6")
    assert_not_equal 429, response.status
  end

  private

  def assert_throttled!(expected_message:, expected_retry_after:)
    body = JSON.parse(response.body)
    assert_equal "rate_limited", body.dig("error", "code").to_s
    assert_includes body.dig("error", "message").to_s, expected_message
    assert_equal expected_retry_after.to_s, response.headers["Retry-After"].to_s
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

  def post_login(email, ip: "1.1.1.1")
    post "/api/v1/login",
         params: { session: { email_address: email, password: "bad" } },
         headers: ip_headers(ip)
  end

  def post_signup(email, ip: "1.1.1.1")
    post "/api/v1/signup",
         params: { user: { name: "Test", email_address: email, password: "short", password_confirmation: "mismatch" } },
         headers: ip_headers(ip)
  end

  def post_password_forgot(email, ip: "1.1.1.1")
    post "/api/v1/password/forgot",
         params: { password: { email_address: email } },
         headers: ip_headers(ip)
  end

  def ip_headers(ip)
    { "REMOTE_ADDR" => ip, "X-Forwarded-For" => ip }
  end
end
