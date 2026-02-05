require "test_helper"
require "jwt"
require "ostruct"

class AuditLogsIncidentResponseTest < ActionDispatch::IntegrationTest
  class FakeStripeEvent
    attr_reader :id, :type, :data

    def initialize(payload)
      @id = payload[:id]
      @type = payload[:type]
      @payload = payload
      @data = OpenStruct.new(object: payload[:data][:object])
    end

    def to_hash
      @payload
    end
  end

  test "creates an audit log on login" do
    user = User.create!(name: "User", email_address: "audit_login@example.com", password: "password", bid_credits: 0)

    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "password" } },
         headers: ip_headers("1.2.3.4").merge("User-Agent" => "Minitest UA")

    assert_response :success
    body = JSON.parse(response.body)

    log = AuditLog.order(:created_at).where(action: "auth.login", user_id: user.id).last
    assert log, "Expected an AuditLog for auth.login"
    assert_equal user.id, log.actor_id
    assert_equal body.fetch("session_token_id"), log.session_token_id
    assert log.request_id.present?
    assert_equal "1.2.3.4", log.ip_address
    assert_equal "Minitest UA", log.user_agent
  end

  test "creates an audit log when a payment is applied via webhook" do
    user = User.create!(
      name: "Buyer",
      email_address: "audit_payment@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    bid_pack = BidPack.create!(name: "Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)

    payload = {
      id: "evt_cs_audit",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_audit_1",
          payment_status: "paid",
          payment_intent: "pi_audit_1",
          metadata: { user_id: user.id, bid_pack_id: bid_pack.id },
          amount_total: 999,
          currency: "usd"
        }
      }
    }

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
    end

    log = AuditLog.order(:created_at).where(action: "payment.applied", user_id: user.id).last
    assert log, "Expected an AuditLog for payment.applied"
    assert_nil log.actor_id
    assert_equal "pi_audit_1", log.payload["stripe_payment_intent_id"]
    assert_equal "cs_audit_1", log.payload["stripe_checkout_session_id"]
    assert log.payload["purchase_id"].present?
  end

  test "creates an audit log when a bid is placed" do
    user = User.create!(
      name: "Bidder",
      email_address: "audit_bid@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("audit_bid"), expires_at: 1.hour.from_now)
    Credits::Apply.apply!(user: user, reason: "seed", amount: 2, idempotency_key: "audit:bid:seed:#{user.id}")

    auction = Auction.create!(
      title: "Audit Bid Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 10.minutes.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    post "/api/v1/auctions/#{auction.id}/bids",
         headers: auth_headers(user, session_token, ip: "2.2.2.2", user_agent: "Minitest UA")

    assert_response :success

    log = AuditLog.order(:created_at).where(action: "auction.bid.placed", actor_id: user.id).last
    assert log, "Expected an AuditLog for auction.bid.placed"
    assert_equal user.id, log.user_id
    assert_equal session_token.id, log.session_token_id
    assert log.request_id.present?
    assert_equal "2.2.2.2", log.ip_address
    assert_equal "Minitest UA", log.user_agent
    assert_equal auction.id, log.payload["auction_id"]
    assert log.payload["bid_id"].present?
  end

  test "creates an audit log for an admin action" do
    admin = create_actor(role: :admin)
    session_token = SessionToken.create!(user: admin, token_digest: SessionToken.digest("audit_admin"), expires_at: 1.hour.from_now)

    post "/api/v1/admin/audit",
         params: { audit: { action: "incident.test", target_type: "User", target_id: admin.id, payload: { "ok" => true } } },
         headers: auth_headers(admin, session_token, user_agent: "Minitest UA")

    assert_response :created
    log = AuditLog.order(:created_at).where(action: "incident.test", actor_id: admin.id).last
    assert log, "Expected an AuditLog for admin audit action"
    assert_equal admin.id, log.user_id
    assert_equal session_token.id, log.session_token_id
    assert log.request_id.present?
    assert_equal "Minitest UA", log.user_agent
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i, ip: "9.9.9.9", user_agent: nil)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    token = encode_jwt(payload)
    headers = ip_headers(ip).merge("Authorization" => "Bearer #{token}")
    headers["User-Agent"] = user_agent if user_agent.present?
    headers
  end

  def ip_headers(ip)
    { "REMOTE_ADDR" => ip, "X-Forwarded-For" => ip }
  end
end
