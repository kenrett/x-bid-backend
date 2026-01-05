require "test_helper"
require "ostruct"

class EmailVerificationMoneyRoutesTest < ActionDispatch::IntegrationTest
  FakeCheckoutCreateSession = Struct.new(:client_secret, keyword_init: true)
  FakeCheckoutMetadata = Struct.new(:user_id, :bid_pack_id, keyword_init: true)
  FakeCheckoutRetrieveSession = Struct.new(
    :id,
    :payment_status,
    :status,
    :payment_intent,
    :metadata,
    :amount_total,
    :currency,
    :customer_email,
    keyword_init: true
  )

  MONEY_ROUTES = [
    "POST /api/v1/auctions/:id/bids",
    "POST /api/v1/checkouts",
    "GET /api/v1/checkout/success",
    "POST /api/v1/me/wins/:auction_id/claim"
  ].freeze

  test "unverified users are blocked on all money-adjacent routes" do
    user = create_actor(role: :user)

    auction = Auction.create!(
      title: "Bid Gate",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
    bid_pack = BidPack.create!(
      name: "Gate Pack",
      bids: 10,
      price: BigDecimal("9.99"),
      highlight: false,
      description: "test",
      active: true
    )

    win_auction = Auction.create!(
      title: "Win Gate",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: user
    )
    win_bid = Bid.create!(user: user, auction: win_auction, amount: BigDecimal("10.00"))
    settlement = AuctionSettlement.create!(
      auction: win_auction,
      winning_user: user,
      winning_bid: win_bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    AuctionFulfillment.create!(auction_settlement: settlement, user: user)

    assert_email_unverified_403! do
      post "/api/v1/auctions/#{auction.id}/bids", headers: auth_headers_for(user)
    end

    assert_email_unverified_403! do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end

    assert_email_unverified_403! do
      get "/api/v1/checkout/success", params: { session_id: "cs_any" }, headers: auth_headers_for(user)
    end

    assert_email_unverified_403! do
      post "/api/v1/me/wins/#{win_auction.id}/claim",
           params: { shipping_address: valid_address },
           headers: auth_headers_for(user)
    end
  end

  test "verified users can complete happy paths on all enumerated money routes" do
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

    bid_pack = BidPack.create!(
      name: "Allowed Pack",
      bids: 10,
      price: BigDecimal("9.99"),
      highlight: false,
      description: "test",
      active: true
    )

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(client_secret: "cs_secret_123") }) do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end
    assert_response :success

    retrieve_session = FakeCheckoutRetrieveSession.new(
      id: "cs_success_123",
      payment_status: "paid",
      status: "complete",
      payment_intent: "pi_123",
      metadata: FakeCheckoutMetadata.new(user_id: user.id, bid_pack_id: bid_pack.id),
      amount_total: 999,
      currency: "usd",
      customer_email: user.email_address
    )
    apply_result = ServiceResult.ok(data: { purchase: OpenStruct.new(id: 123) }, idempotent: false)

    Stripe::Checkout::Session.stub(:retrieve, ->(_session_id) { retrieve_session }) do
      Payments::ApplyBidPackPurchase.stub(:call!, ->(**_kwargs) { apply_result }) do
        get "/api/v1/checkout/success", params: { session_id: "cs_success_123" }, headers: auth_headers_for(user)
      end
    end
    assert_response :success

    win_auction = Auction.create!(
      title: "Win Allowed",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: user
    )
    win_bid = Bid.create!(user: user, auction: win_auction, amount: BigDecimal("10.00"))
    settlement = AuctionSettlement.create!(
      auction: win_auction,
      winning_user: user,
      winning_bid: win_bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    AuctionFulfillment.create!(auction_settlement: settlement, user: user)

    post "/api/v1/me/wins/#{win_auction.id}/claim",
         params: { shipping_address: valid_address },
         headers: auth_headers_for(user)
    assert_response :success
  end

  private

  def valid_address
    {
      name: "User",
      line1: "123 Main",
      city: "Portland",
      state: "OR",
      postal_code: "97201",
      country: "US"
    }
  end

  def assert_email_unverified_403!
    yield
    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "email_unverified", body.dig("error", "code").to_s
    assert_equal "Verify your email to continue.", body.dig("error", "message")
  rescue => e
    raise "#{e.class}: #{e.message}\nRoutes under test: #{MONEY_ROUTES.join(', ')}"
  end
end
