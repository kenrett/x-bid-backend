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
    assert_includes response.body, "rate_limited"
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
        post "/api/v1/auctions/1/bids", headers: { "REMOTE_ADDR" => "3.3.3.3", "HTTP_AUTHORIZATION" => "Bearer token" }
        assert_not_equal 429, response.status
      end

      post "/api/v1/auctions/1/bids", headers: { "REMOTE_ADDR" => "3.3.3.3", "HTTP_AUTHORIZATION" => "Bearer token" }
      assert_response :too_many_requests
    end
  end

  private

  def stub_authentication_and_bids_controller
    original_authenticate = Api::V1::BidsController.instance_method(:authenticate_request!)
    original_create = Api::V1::BidsController.instance_method(:create)

    Api::V1::BidsController.define_method(:authenticate_request!) { }
    Api::V1::BidsController.define_method(:create) { head :ok }

    yield
  ensure
    Api::V1::BidsController.define_method(:authenticate_request!, original_authenticate)
    Api::V1::BidsController.define_method(:create, original_create)
  end

  def post_login(email, ip: "1.1.1.1")
    post "/api/v1/login",
         params: { session: { email_address: email, password: "bad" } },
         headers: { "REMOTE_ADDR" => ip }
  end
end
