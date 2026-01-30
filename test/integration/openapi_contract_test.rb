require "test_helper"
class OpenapiContractTest < ActionDispatch::IntegrationTest
  include OpenapiContractHelpers

  FakeCheckoutCreateSession = Struct.new(:id, :client_secret, keyword_init: true)

  test "POST /api/v1/signup matches OpenAPI (201 + 422)" do
    post "/api/v1/signup",
         params: {
           user: {
             name: "User",
             email_address: "openapi_signup@example.com",
             password: "password",
             password_confirmation: "password"
           }
         }

    assert_response :created
    assert_openapi_response_schema!(method: :post, path: "/api/v1/signup", status: response.status)

    headers = csrf_headers
    post "/api/v1/signup", params: { user: { email_address: "openapi_signup_bad@example.com" } }, headers: headers

    assert_response :unprocessable_content
    assert_openapi_response_schema!(method: :post, path: "/api/v1/signup", status: response.status)
  end

  test "POST /api/v1/login matches OpenAPI (200 + 401)" do
    user = User.create!(
      name: "User",
      email_address: "openapi_login@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }

    assert_response :success
    assert_openapi_response_schema!(method: :post, path: "/api/v1/login", status: response.status)

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "wrong" } }

    assert_response :unauthorized
    assert_openapi_response_schema!(method: :post, path: "/api/v1/login", status: response.status)
  end

  test "POST /api/v1/session/refresh matches OpenAPI (200 + 401)" do
    user = User.create!(
      name: "User",
      email_address: "openapi_refresh@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :success
    login_body = JSON.parse(response.body)
    refresh_token = login_body.fetch("refresh_token")

    headers = csrf_headers
    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }, headers: headers

    assert_response :success
    assert_openapi_response_schema!(method: :post, path: "/api/v1/session/refresh", status: response.status)

    post "/api/v1/session/refresh", params: { refresh_token: "rt_invalid" }, headers: headers

    assert_response :unauthorized
    assert_openapi_response_schema!(method: :post, path: "/api/v1/session/refresh", status: response.status)
  end

  test "GET /api/v1/logged_in matches OpenAPI (200 + 401)" do
    user = create_actor(role: :user)

    get "/api/v1/logged_in", headers: auth_headers_for(user)

    assert_response :success
    assert_openapi_response_schema!(method: :get, path: "/api/v1/logged_in", status: response.status)

    get "/api/v1/logged_in"

    assert_response :unauthorized
    assert_openapi_response_schema!(method: :get, path: "/api/v1/logged_in", status: response.status)
  end

  test "POST /api/v1/checkouts matches OpenAPI (200 + 401)" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(id: "cs_openapi", client_secret: "cs_secret_123") }) do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end

    assert_response :success
    assert_openapi_response_schema!(method: :post, path: "/api/v1/checkouts", status: response.status)

    post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }

    assert_response :unauthorized
    assert_openapi_response_schema!(method: :post, path: "/api/v1/checkouts", status: response.status)
  end

  test "GET /api/v1/checkout/success matches OpenAPI (200 + 404)" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_checkout_session_id: "cs_openapi_success",
      status: "created"
    )

    get "/api/v1/checkout/success", params: { session_id: purchase.stripe_checkout_session_id }, headers: auth_headers_for(user)

    assert_response :success
    assert_openapi_response_schema!(method: :get, path: "/api/v1/checkout/success", status: response.status)

    get "/api/v1/checkout/success", params: { session_id: "cs_openapi_unpaid" }, headers: auth_headers_for(user)

    assert_response :not_found
    assert_openapi_response_schema!(method: :get, path: "/api/v1/checkout/success", status: response.status)
  end

  test "POST /api/v1/auctions/:id/bids matches OpenAPI (200 + 401)" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    Credits::Apply.apply!(user: user, reason: "seed_grant", amount: 1, idempotency_key: "openapi:bid:seed:#{user.id}")
    auction = Auction.create!(
      title: "OpenAPI Bid",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    post "/api/v1/auctions/#{auction.id}/bids", headers: auth_headers_for(user)

    assert_response :success
    assert_openapi_response_schema!(method: :post, path: "/api/v1/auctions/#{auction.id}/bids", status: response.status)

    post "/api/v1/auctions/#{auction.id}/bids"

    assert_response :unauthorized
    assert_openapi_response_schema!(method: :post, path: "/api/v1/auctions/#{auction.id}/bids", status: response.status)
  end
end
