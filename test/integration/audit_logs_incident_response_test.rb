require "test_helper"
require "jwt"
require "ostruct"

class AuditLogsIncidentResponseTest < ActionDispatch::IntegrationTest
  FakeCheckoutSession = Struct.new(
    :id,
    :payment_status,
    :payment_intent,
    :customer_email,
    :metadata,
    :amount_total,
    :amount_subtotal,
    :currency,
    keyword_init: true
  )

  test "creates an audit log on login" do
    user = User.create!(name: "User", email_address: "audit_login@example.com", password: "password", bid_credits: 0)

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }, headers: ip_headers("1.2.3.4")

    assert_response :success
    body = JSON.parse(response.body)

    log = AuditLog.order(:created_at).where(action: "auth.login", user_id: user.id).last
    assert log, "Expected an AuditLog for auth.login"
    assert_equal user.id, log.actor_id
    assert_equal body.fetch("session_token_id"), log.session_token_id
    assert log.request_id.present?
    assert_equal "1.2.3.4", log.ip_address
  end

  test "creates an audit log when a payment is applied via checkout success" do
    user = User.create!(
      name: "Buyer",
      email_address: "audit_payment@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("audit_payment"), expires_at: 1.hour.from_now)
    bid_pack = BidPack.create!(name: "Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)

    checkout_session = FakeCheckoutSession.new(
      id: "cs_audit_1",
      payment_status: "paid",
      payment_intent: "pi_audit_1",
      customer_email: user.email_address,
      metadata: OpenStruct.new(bid_pack_id: bid_pack.id, user_id: user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_audit_1" }, headers: auth_headers(user, session_token)
    end
    assert_response :success

    log = AuditLog.order(:created_at).where(action: "payment.applied", user_id: user.id).last
    assert log, "Expected an AuditLog for payment.applied"
    assert_equal user.id, log.actor_id
    assert_equal session_token.id, log.session_token_id
    assert log.request_id.present?
    assert_equal "pi_audit_1", log.payload["stripe_payment_intent_id"]
    assert_equal "cs_audit_1", log.payload["stripe_checkout_session_id"]
    assert log.payload["purchase_id"].present?
  end

  test "creates an audit log for an admin action" do
    admin = create_actor(role: :admin)
    session_token = SessionToken.create!(user: admin, token_digest: SessionToken.digest("audit_admin"), expires_at: 1.hour.from_now)

    post "/api/v1/admin/audit",
         params: { audit: { action: "incident.test", target_type: "User", target_id: admin.id, payload: { "ok" => true } } },
         headers: auth_headers(admin, session_token)

    assert_response :created
    log = AuditLog.order(:created_at).where(action: "incident.test", actor_id: admin.id).last
    assert log, "Expected an AuditLog for admin audit action"
    assert_equal admin.id, log.user_id
    assert_equal session_token.id, log.session_token_id
    assert log.request_id.present?
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i, ip: "9.9.9.9")
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    ip_headers(ip).merge("Authorization" => "Bearer #{token}")
  end

  def ip_headers(ip)
    { "REMOTE_ADDR" => ip, "X-Forwarded-For" => ip }
  end
end
