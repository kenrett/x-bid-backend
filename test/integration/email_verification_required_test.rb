require "test_helper"
require "ostruct"

class EmailVerificationRequiredTest < ActionDispatch::IntegrationTest
  FakeCheckoutCreateSession = Struct.new(:client_secret, keyword_init: true)

  test "blocks bidding when email is unverified" do
    user = create_actor(role: :user)
    auction = Auction.create!(
      title: "Bid Gate",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    post "/api/v1/auctions/#{auction.id}/bids", headers: auth_headers_for(user)

    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "email_unverified", body.dig("error", "code").to_s
    assert_equal "Verify your email to continue.", body.dig("error", "message")
  end

  test "allows bidding when email is verified" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    auction = Auction.create!(
      title: "Bid Allowed",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
    Credits::Apply.apply!(user: user, reason: "seed_grant", amount: 1, idempotency_key: "test:bid:seed:#{user.id}")

    post "/api/v1/auctions/#{auction.id}/bids", headers: auth_headers_for(user)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
  end

  test "blocks checkout session creation when email is unverified" do
    user = create_actor(role: :user)
    bid_pack = BidPack.create!(name: "Gate Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)

    post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)

    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "email_unverified", body.dig("error", "code").to_s
    assert_equal "Verify your email to continue.", body.dig("error", "message")
  end

  test "allows checkout session creation when email is verified" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Allowed Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(client_secret: "cs_secret_123") }) do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "cs_secret_123", body["clientSecret"]
  end

  test "blocks checkout success apply when email is unverified" do
    user = create_actor(role: :user)

    get "/api/v1/checkout/success", params: { session_id: "cs_any" }, headers: auth_headers_for(user)

    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "email_unverified", body.dig("error", "code").to_s
    assert_equal "Verify your email to continue.", body.dig("error", "message")
  end
end
