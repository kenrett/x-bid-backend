require "test_helper"
require "jwt"

class AdminFulfillmentsApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin_fulfillment@example.com", password: "password", role: :admin, bid_credits: 0)
    @admin_session = SessionToken.create!(user: @admin, token_digest: SessionToken.digest("raw-admin"), expires_at: 1.hour.from_now)

    @user = User.create!(name: "Winner", email_address: "winner_admin_fulfillment@example.com", password: "password", bid_credits: 0)
    @user_session = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw-user"), expires_at: 1.hour.from_now)

    @auction = Auction.create!(
      title: "Win",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: @user
    )
    bid = Bid.create!(user: @user, auction: @auction, amount: BigDecimal("10.00"))
    @settlement = AuctionSettlement.create!(
      auction: @auction,
      winning_user: @user,
      winning_bid: bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    @fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @user)
  end

  test "enforces admin role checks" do
    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/process",
         params: { shipping_cost_cents: 500 },
         headers: auth_headers(@user, @user_session)

    assert_response :forbidden
  end

  test "process rejects invalid transitions" do
    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/process",
         params: { shipping_cost_cents: 500 },
         headers: auth_headers(@admin, @admin_session)

    assert_response :unprocessable_content
    assert_equal "pending", @fulfillment.reload.status
  end

  test "process transitions claimed -> processing, sets cost + notes, and audits" do
    @fulfillment.transition_to!(:claimed)

    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/process",
         params: { shipping_cost_cents: 500, notes: "pack carefully" },
         headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "processing", body.fetch("status")
    assert_equal 500, body.fetch("shipping_cost_cents")
    assert_equal "pack carefully", body.dig("metadata", "admin_notes", "processing")

    log = AuditLog.order(created_at: :desc).first
    assert_equal "fulfillment.process", log.action
    assert_equal @admin.id, log.actor_id
    assert_equal "AuctionFulfillment", log.target_type
    assert_equal @fulfillment.id, log.target_id
    assert_equal 500, log.payload["shipping_cost_cents"]
  end

  test "ship rejects invalid transitions" do
    @fulfillment.transition_to!(:claimed)

    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/ship",
         params: { shipping_carrier: "ups", tracking_number: "1Z999" },
         headers: auth_headers(@admin, @admin_session)

    assert_response :unprocessable_content
    assert_equal "claimed", @fulfillment.reload.status
  end

  test "ship transitions processing -> shipped and audits" do
    @fulfillment.transition_to!(:claimed)
    @fulfillment.transition_to!(:processing)

    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/ship",
         params: { shipping_carrier: "ups", tracking_number: "1Z999" },
         headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "shipped", body.fetch("status")
    assert_equal "ups", body.fetch("shipping_carrier")
    assert_equal "1Z999", body.fetch("tracking_number")

    log = AuditLog.order(created_at: :desc).first
    assert_equal "fulfillment.ship", log.action
    assert_equal @admin.id, log.actor_id
    assert_equal @fulfillment.id, log.target_id
    assert_equal "ups", log.payload["shipping_carrier"]
  end

  test "complete transitions shipped -> complete" do
    @fulfillment.transition_to!(:claimed)
    @fulfillment.transition_to!(:processing)
    @fulfillment.transition_to!(:shipped)

    post "/api/v1/admin/fulfillments/#{@fulfillment.id}/complete",
         headers: auth_headers(@admin, @admin_session)

    assert_response :success
    assert_equal "complete", JSON.parse(response.body).fetch("status")
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
