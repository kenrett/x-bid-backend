require "test_helper"

class RackAttackTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.reset!
  end

  test "throttles login by normalized email and IP" do
    throttle = Rack::Attack.throttles.fetch("login/email/short")

    throttle.limit.times do
      post_login("User@example.com")
      assert_response :unauthorized
    end

    post_login("user@example.com")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many login attempts", expected_retry_after: throttle.period.to_i)

    post_login("other@example.com")
    assert_response :unauthorized
  end

  test "login throttle resets after window" do
    throttle = Rack::Attack.throttles.fetch("login/email/short")

    throttle.limit.times do
      post_login("User@example.com")
      assert_response :unauthorized
    end

    post_login("user@example.com")
    assert_response :too_many_requests

    travel throttle.period + 1.second do
      post_login("user@example.com")
      assert_response :unauthorized
    end
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
    throttle = Rack::Attack.throttles.fetch("bids/ip")

    stub_authentication_and_bids_controller do
      throttle.limit.times do
        post "/api/v1/auctions/1/bids", headers: ip_headers("3.3.3.3").merge("HTTP_AUTHORIZATION" => "Bearer token")
        assert_not_equal 429, response.status
      end

      post "/api/v1/auctions/1/bids", headers: ip_headers("3.3.3.3").merge("HTTP_AUTHORIZATION" => "Bearer token")
      assert_response :too_many_requests
      assert_throttled!(expected_message: "Too many bid attempts", expected_retry_after: throttle.period.to_i)

      post "/api/v1/auctions/1/bids", headers: ip_headers("4.4.4.4").merge("HTTP_AUTHORIZATION" => "Bearer token")
      assert_response :ok
    end
  end

  test "throttles bidding by user_id across IPs" do
    throttle = Rack::Attack.throttles.fetch("bids/user")

    stub_authentication_and_bids_controller do
      token = jwt_for(user_id: 123, session_token_id: 1)

      throttle.limit.times do |idx|
        ip = "7.7.7.#{idx % 10}"
        post "/api/v1/auctions/1/bids", headers: ip_headers(ip).merge("HTTP_AUTHORIZATION" => "Bearer #{token}")
        assert_not_equal 429, response.status
      end

      post "/api/v1/auctions/1/bids", headers: ip_headers("8.8.8.8").merge("HTTP_AUTHORIZATION" => "Bearer #{token}")
      assert_response :too_many_requests
      assert_throttled!(expected_message: "Too many bid attempts", expected_retry_after: throttle.period.to_i)

      other_token = jwt_for(user_id: 456, session_token_id: 2)
      post "/api/v1/auctions/1/bids", headers: ip_headers("8.8.8.8").merge("HTTP_AUTHORIZATION" => "Bearer #{other_token}")
      assert_response :ok
    end
  end

  test "throttles signup by normalized email and IP" do
    throttle = Rack::Attack.throttles.fetch("signup/email")

    throttle.limit.times do
      post_signup("NewUser@example.com")
      assert_response :unprocessable_content
    end

    post_signup("newuser@example.com")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many signup attempts", expected_retry_after: throttle.period.to_i)

    post_signup("other_signup@example.com")
    assert_response :unprocessable_content
  end

  test "throttles password reset by normalized email" do
    throttle = Rack::Attack.throttles.fetch("password_reset/email")

    stub_password_resets_controller do
      throttle.limit.times do
        post_password_forgot("ResetUser@example.com")
        assert_response :accepted
      end

      post_password_forgot("resetuser@example.com")
      assert_response :too_many_requests
      assert_throttled!(expected_message: "Too many password attempts", expected_retry_after: throttle.period.to_i)

      post_password_forgot("other_reset@example.com")
      assert_response :accepted
    end
  end

  test "throttles checkout creation by IP" do
    throttle = Rack::Attack.throttles.fetch("checkout/ip")

    throttle.limit.times do
      post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("5.5.5.5")
      assert_not_equal 429, response.status
    end

    post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("5.5.5.5")
    assert_response :too_many_requests
    assert_throttled!(expected_message: "Too many checkout attempts", expected_retry_after: throttle.period.to_i)

    post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("6.6.6.6")
    assert_not_equal 429, response.status
  end

  test "checkout throttle resets after window" do
    throttle = Rack::Attack.throttles.fetch("checkout/ip")

    throttle.limit.times do
      post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("9.9.9.9")
      assert_not_equal 429, response.status
    end

    post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("9.9.9.9")
    assert_response :too_many_requests

    travel throttle.period + 1.second do
      post "/api/v1/checkouts", params: { bid_pack_id: 1 }, headers: ip_headers("9.9.9.9")
      assert_not_equal 429, response.status
    end
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

  def stub_password_resets_controller
    original_create = Api::V1::PasswordResetsController.instance_method(:create)
    Api::V1::PasswordResetsController.define_method(:create) { head :accepted }
    yield
  ensure
    Api::V1::PasswordResetsController.define_method(:create, original_create)
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

  def jwt_for(user_id:, session_token_id:)
    payload = { "user_id" => user_id, "session_token_id" => session_token_id, "exp" => 1.hour.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end
end
