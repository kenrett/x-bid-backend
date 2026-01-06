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

    8.times do
      post "/api/v1/login",
           params: { session: { email_address: user.email_address, password: "wrong" } },
           headers: ip_headers("1.1.1.1")
      assert_response :unauthorized
    end

    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "wrong" } },
         headers: ip_headers("1.1.1.1")
    assert_response :too_many_requests
    assert_rate_limited!(expected_retry_after: 10.minutes.to_i)

    travel 10.minutes + 1.second do
      post "/api/v1/login",
           params: { session: { email_address: user.email_address, password: "wrong" } },
           headers: ip_headers("1.1.1.1")
      assert_response :unauthorized
    end
  end

  test "POST /api/v1/signup returns 429 with canonical envelope and Retry-After" do
    6.times do
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
    assert_rate_limited!(expected_retry_after: 1.hour.to_i)
  end

  test "POST /api/v1/auctions/:id/bids returns 429 with canonical envelope and Retry-After" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    Credits::Apply.apply!(user: user, reason: "seed_grant", amount: 55, idempotency_key: "test:rate:bid:seed:#{user.id}")

    auction = Auction.create!(
      title: "Rate Limit Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    headers = auth_headers_for(user).merge(ip_headers("3.3.3.3"))

    50.times do
      post "/api/v1/auctions/#{auction.id}/bids", headers: headers
      assert_response :success
    end

    post "/api/v1/auctions/#{auction.id}/bids", headers: headers
    assert_response :too_many_requests
    assert_rate_limited!(expected_retry_after: 1.minute.to_i)

    travel 61.seconds do
      post "/api/v1/auctions/#{auction.id}/bids", headers: headers
      assert_response :success
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
end
