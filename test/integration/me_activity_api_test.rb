require "test_helper"
require "jwt"
require "securerandom"

class MeActivityApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(
      user: @other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    @auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
  end

  test "GET /api/v1/me/activity returns only current user's activity" do
    Bid.create!(user: @user, auction: @auction, amount: BigDecimal("2.00"))
    Bid.create!(user: @other_user, auction: @auction, amount: BigDecimal("3.00"))
    AuctionWatch.create!(user: @user, auction: @auction)
    AuctionWatch.create!(user: @other_user, auction: @auction)

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    types = body.fetch("items").map { |item| item["type"] }.uniq
    assert_includes types, "bid_placed"
    assert_includes types, "auction_watched"

    assert_equal 2, body.fetch("items").length
  end

  test "activity contains bid item shape" do
    bid = Bid.create!(user: @user, auction: @auction, amount: BigDecimal("2.00"))

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    item = JSON.parse(response.body).fetch("items").first
    assert_equal "bid_placed", item["type"]
    assert item["created_at"].present?
    assert_equal @auction.id, item.dig("auction", "id")
    assert_equal @auction.title, item.dig("auction", "title")
    assert_equal @auction.external_status, item.dig("auction", "status")
    assert_equal bid.id, item.dig("data", "bid_id")
    assert_equal "2.0", item.dig("data", "amount")
  end

  test "activity contains outcome items when auctions close" do
    ended_auction = Auction.create!(
      title: "Ended",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("1.00"),
      status: :ended,
      winning_user: @other_user
    )
    Bid.create!(user: @user, auction: ended_auction, amount: BigDecimal("2.00"))

    won_auction = Auction.create!(
      title: "Won",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("1.00"),
      status: :ended,
      winning_user: @user
    )

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    types = body.fetch("items").map { |item| item["type"] }
    assert_includes types, "auction_lost"
    assert_includes types, "auction_won"
  end

  test "activity includes purchase_completed items (for current user only) with expected shape" do
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 100, price: 1.0, active: true)

    stripe_payment_intent_id = "pi_activity_api_#{SecureRandom.hex(8)}"
    other_stripe_payment_intent_id = "pi_activity_api_other_#{SecureRandom.hex(8)}"

    purchase = Purchase.create!(
      user: @user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 123,
      currency: "usd",
      stripe_payment_intent_id: stripe_payment_intent_id,
      receipt_status: :available,
      receipt_url: "https://stripe.example/receipts/rcpt_api_1",
      stripe_charge_id: "ch_api_1",
      created_at: 10.days.ago
    )
    MoneyEvent.create!(
      user: @user,
      event_type: :purchase,
      amount_cents: purchase.amount_cents,
      currency: purchase.currency,
      source_type: "StripePaymentIntent",
      source_id: stripe_payment_intent_id,
      occurred_at: 2.days.ago,
      metadata: { purchase_id: purchase.id }
    )

    other_purchase = Purchase.create!(
      user: @other_user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: other_stripe_payment_intent_id
    )

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    item = body.fetch("items").find { |row| row.fetch("type") == "purchase_completed" }
    assert item.present?

    assert item["created_at"].present?
    assert item["occurred_at"].present?
    assert_nil item["auction"]

    data = item.fetch("data")
    assert_equal purchase.id, data.fetch("purchase_id")
    assert_equal bid_pack.id, data.fetch("bid_pack_id")
    assert_equal bid_pack.name, data.fetch("bid_pack_name")
    assert_equal bid_pack.bids, data.fetch("credits_added")
    assert_equal 123, data.fetch("amount_cents")
    assert_equal "usd", data.fetch("currency")
    assert_equal "applied", data.fetch("payment_status")
    assert_equal "available", data.fetch("receipt_status")
    assert_equal "https://stripe.example/receipts/rcpt_api_1", data.fetch("receipt_url")
    assert_equal stripe_payment_intent_id, data.fetch("stripe_payment_intent_id")
    assert_equal "ch_api_1", data.fetch("stripe_charge_id")

    purchase_items = body.fetch("items").select { |row| row.fetch("type") == "purchase_completed" }
    assert_equal [ purchase.id ], purchase_items.map { |row| row.dig("data", "purchase_id") }
  end

  test "activity includes fulfillment_status_changed items for fulfillment transitions" do
    ended_auction = Auction.create!(
      title: "Ended",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("1.00"),
      status: :ended,
      winning_user: @user
    )
    bid = Bid.create!(user: @user, auction: ended_auction, amount: BigDecimal("2.00"))
    settlement = AuctionSettlement.create!(
      auction: ended_auction,
      winning_user: @user,
      winning_bid: bid,
      final_price: BigDecimal("2.00"),
      currency: "usd",
      status: :paid,
      ended_at: ended_auction.end_time
    )

    fulfillment = AuctionFulfillment.create!(auction_settlement: settlement, user: @user)
    fulfillment.transition_to!(:claimed, occurred_at: 1.day.ago)

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    item = body.fetch("items").find { |row| row.fetch("type") == "fulfillment_status_changed" }
    assert item.present?
    assert item["occurred_at"].present?
    assert item["created_at"].present?
    assert_equal ended_auction.id, item.dig("auction", "id")

    data = item.fetch("data")
    assert_equal ended_auction.id, data.fetch("auction_id")
    assert_equal settlement.id, data.fetch("settlement_id")
    assert_equal fulfillment.id, data.fetch("fulfillment_id")
    assert_equal "pending", data.fetch("from_status")
    assert_equal "claimed", data.fetch("to_status")
  end

  test "removing a watch emits watch_removed and it appears in activity" do
    watched_auction = Auction.create!(
      title: "Watched",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    watch = AuctionWatch.create!(user: @user, auction: watched_auction)

    delete "/api/v1/auctions/#{watched_auction.id}/watch", headers: auth_headers(@user, @session_token)
    assert_response :no_content
    assert_nil AuctionWatch.find_by(id: watch.id)

    get "/api/v1/me/activity", headers: auth_headers(@user, @session_token)
    assert_response :success

    body = JSON.parse(response.body)
    item = body.fetch("items").find { |row| row.fetch("type") == "watch_removed" && row.dig("data", "watch_id") == watch.id }
    assert item.present?
    assert item["occurred_at"].present?
    assert_equal watched_auction.id, item.dig("data", "auction_id")
    assert_equal watched_auction.id, item.dig("auction", "id")
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
