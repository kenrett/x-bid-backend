require "test_helper"
require "jwt"

class AdminPaymentsApiTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(
      name: "Admin",
      email_address: "admin@example.com",
      password: "password",
      role: :admin,
      bid_credits: 0
    )
    @admin_session = SessionToken.create!(
      user: @admin,
      token_digest: SessionToken.digest("raw"),
      expires_at: 1.hour.from_now
    )

    @bid_pack = BidPack.create!(
      name: "Starter",
      bids: 10,
      price: BigDecimal("9.99"),
      highlight: false,
      description: "test pack",
      active: true
    )
  end

  test "returns payments for admins" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    get "/api/v1/admin/payments", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size

    payment = body.first
    assert_equal purchase.id, payment["id"]
    assert_equal user.email_address, payment["user_email"]
    assert_in_delta @bid_pack.price.to_f, payment["amount"].to_f, 0.001
    assert_equal purchase.status, payment["status"]
    assert payment["created_at"].present?
    assert_equal purchase.stripe_checkout_session_id, payment["stripe_checkout_session_id"]
    assert_equal purchase.stripe_payment_intent_id, payment["stripe_payment_intent_id"]
    assert_nil payment["stripe_event_id"]
  end

  test "filters payments by user email search" do
    matching_user = create_user(email: "match@example.com")
    other_user = create_user(email: "other@example.com")
    create_purchase(user: matching_user)
    create_purchase(user: other_user)

    get "/api/v1/admin/payments", params: { search: "match" }, headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal matching_user.email_address, body.first["user_email"]
  end

  test "rejects non-admins" do
    user = create_user(email: "user@example.com", role: :user)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    get "/api/v1/admin/payments", headers: auth_headers(user, session_token)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error_code"]
    assert_equal "Admin privileges required", body["message"]
  end

  test "routes refund through Admin::Payments::IssueRefund" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    fake_service = Class.new do
      def initialize(payment)
        @payment = payment
      end

      def call
        @payment.update!(status: "refunded", refunded_cents: 500)
        ServiceResult.ok(code: :refunded, data: { refund_id: "re_fake" })
      end
    end

    captured_kwargs = nil
    Admin::Payments::IssueRefund.stub(:new, ->(**kwargs) { captured_kwargs = kwargs; fake_service.new(kwargs[:payment]) }) do
      post "/api/v1/admin/payments/#{purchase.id}/refund", params: { amount_cents: 500, reason: "mistake" }, headers: auth_headers(@admin, @admin_session)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "refunded", body["status"]
    assert_in_delta 9.99, body["amount"].to_f, 0.001
    assert_equal 500, body["refunded_cents"]
    assert_equal "re_fake", body["refund_id"]
    assert_equal @admin, captured_kwargs[:actor]
    assert_equal purchase, captured_kwargs[:payment]
    assert_equal "mistake", captured_kwargs[:reason]
  end

  test "shows payment reconciliation with matching ledger entry" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    credit = CreditTransaction.create!(
      user: user,
      purchase: purchase,
      kind: :grant,
      amount: @bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      metadata: {}
    )
    Credits::RebuildBalance.call!(user: user)

    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal user.email_address, body.dig("purchase", "user_email")
    assert_equal purchase.amount_cents, body.dig("purchase", "amount_cents")
    assert_equal purchase.currency, body.dig("purchase", "currency")
    assert_equal purchase.status, body.dig("purchase", "status")
    assert_equal purchase.stripe_payment_intent_id, body.dig("purchase", "stripe_payment_intent_id")

    txs = body["credit_transactions"]
    assert_equal 1, txs.size
    assert_equal credit.id, txs.first["id"]
    assert_equal "grant", txs.first["kind"]
    assert_equal @bid_pack.bids, txs.first["amount"]
    assert_equal "purchase:#{purchase.id}:grant", txs.first["idempotency_key"]

    audit = body["balance_audit"]
    assert_equal true, audit["matches"]
    assert_equal user.reload.bid_credits, audit["cached"]
    assert_equal user.reload.bid_credits, audit["derived"]
  end

  test "shows empty credit transaction list when ledger entry missing" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal [], body["credit_transactions"]
  end

  test "balance audit mismatch surfaces correctly" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    CreditTransaction.create!(
      user: user,
      purchase: purchase,
      kind: :grant,
      amount: @bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      metadata: {}
    )
    Credits::RebuildBalance.call!(user: user)
    user.update_columns(bid_credits: user.bid_credits + 1)

    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    audit = JSON.parse(response.body)["balance_audit"]
    assert_equal false, audit["matches"]
    assert_equal user.reload.bid_credits, audit["cached"]
    assert_equal Credits::Balance.for_user(user), audit["derived"]
  end

  test "repair_credits creates missing ledger row and returns reconciliation view" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    assert_equal 0, CreditTransaction.where(purchase_id: purchase.id).count

    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers(@admin, @admin_session)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["idempotent"]
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal 1, body["credit_transactions"].size
    assert_equal true, body.dig("balance_audit", "matches")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  test "repair_credits is safe to call twice" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers(@admin, @admin_session)
    assert_response :success
    body1 = JSON.parse(response.body)
    assert_equal false, body1["idempotent"]

    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers(@admin, @admin_session)
    assert_response :success
    body2 = JSON.parse(response.body)
    assert_equal true, body2["idempotent"]

    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  private

  def create_user(email:, role: :user)
    User.create!(
      name: "User",
      email_address: email,
      password: "password",
      role: role,
      bid_credits: 0
    )
  end

  def create_purchase(user:)
    Purchase.create!(
      user: user,
      bid_pack: @bid_pack,
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      stripe_checkout_session_id: SecureRandom.uuid,
      stripe_payment_intent_id: SecureRandom.uuid,
      status: "completed"
    )
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
