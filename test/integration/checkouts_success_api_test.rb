require "test_helper"
require "jwt"
require "ostruct"

class CheckoutsSuccessApiTest < ActionDispatch::IntegrationTest
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

  def setup
    @user = User.create!(
      name: "Buyer",
      email_address: "buyer@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    @session_token = SessionToken.create!(
      user: @user,
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

  test "double-click is idempotent" do
    checkout_session = FakeCheckoutSession.new(
      id: "cs_123",
      payment_status: "paid",
      payment_intent: "pi_123",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_123" }, headers: auth_headers(@user, @session_token)
      assert_response :success
      body1 = JSON.parse(response.body)
      assert_equal false, body1["idempotent"]
      assert body1["purchaseId"].present?
      assert_equal 10, body1["updated_bid_credits"]

      get "/api/v1/checkout/success", params: { session_id: "cs_123" }, headers: auth_headers(@user, @session_token)
      assert_response :success
      body2 = JSON.parse(response.body)
      assert_equal true, body2["idempotent"]
      assert_equal body1["purchaseId"], body2["purchaseId"]
      assert_equal 10, body2["updated_bid_credits"]
    end
  end

  test "retries on record-not-unique and still succeeds" do
    checkout_session = FakeCheckoutSession.new(
      id: "cs_456",
      payment_status: "paid",
      payment_intent: "pi_456",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    original = Payments::ApplyBidPackPurchase.method(:call!)
    attempts = 0

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      Payments::ApplyBidPackPurchase.stub(:call!, lambda { |**kwargs|
        attempts += 1
        raise ActiveRecord::RecordNotUnique if attempts == 1
        original.call(**kwargs)
      }) do
        get "/api/v1/checkout/success", params: { session_id: "cs_456" }, headers: auth_headers(@user, @session_token)
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "success", body["status"]
    assert_equal 10, body["updated_bid_credits"]
    assert_equal 2, attempts
  end

  test "success after webhook already applied returns idempotent true" do
    webhook_apply = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: nil,
      stripe_payment_intent_id: "pi_789",
      stripe_event_id: "evt_789",
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      source: "stripe_webhook"
    )
    assert webhook_apply.ok?
    assert_equal 10, @user.reload.bid_credits

    checkout_session = FakeCheckoutSession.new(
      id: "cs_789",
      payment_status: "paid",
      payment_intent: "pi_789",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_789" }, headers: auth_headers(@user, @session_token)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["idempotent"]
    assert_equal 10, body["updated_bid_credits"]
  end

  test "a paid session for user A cannot be used by user B" do
    other_user = User.create!(
      name: "Other",
      email_address: "other@example.com",
      password: "password",
      role: :user,
      bid_credits: 0,
      email_verified_at: Time.current
    )
    other_token = SessionToken.create!(
      user: other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    checkout_session = FakeCheckoutSession.new(
      id: "cs_999",
      payment_status: "paid",
      payment_intent: "pi_999",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_999" }, headers: auth_headers(other_user, other_token)
    end

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body.dig("error", "code").to_s
    assert_match(/does not belong/i, body.dig("error", "message"))
    assert_equal 0, other_user.reload.bid_credits
    assert_nil Purchase.find_by(stripe_payment_intent_id: "pi_999")
  end

  test "returns a clean error when payment is not completed" do
    checkout_session = FakeCheckoutSession.new(
      id: "cs_unpaid",
      payment_status: "unpaid",
      payment_intent: "pi_unpaid",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_unpaid" }, headers: auth_headers(@user, @session_token)
    end

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "payment_not_completed", body.dig("error", "code").to_s
    assert_equal "Payment not completed.", body.dig("error", "message")
  end

  test "uses session.amount_total and session.currency when present" do
    checkout_session = FakeCheckoutSession.new(
      id: "cs_amount_total",
      payment_status: "paid",
      payment_intent: "pi_amount_total",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "cad"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_amount_total" }, headers: auth_headers(@user, @session_token)
    end

    assert_response :success
    purchase = Purchase.find_by!(stripe_checkout_session_id: "cs_amount_total")
    assert_equal 999, purchase.amount_cents
    assert_equal "cad", purchase.currency
  end

  test "rejects checkout sessions with amount mismatch" do
    checkout_session = FakeCheckoutSession.new(
      id: "cs_amount_mismatch",
      payment_status: "paid",
      payment_intent: "pi_amount_mismatch",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 1000,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success", params: { session_id: "cs_amount_mismatch" }, headers: auth_headers(@user, @session_token)
    end

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "amount_mismatch", body.dig("error", "code").to_s
    assert_match(/amount mismatch/i, body.dig("error", "message"))
    assert_equal 0, @user.reload.bid_credits
    assert_nil Purchase.find_by(stripe_checkout_session_id: "cs_amount_mismatch")
  end

  test "rejects when params bid_pack_id differs from session metadata" do
    other_pack = BidPack.create!(
      name: "Other Pack",
      bids: 20,
      price: BigDecimal("19.99"),
      highlight: false,
      description: "other pack",
      active: true
    )

    checkout_session = FakeCheckoutSession.new(
      id: "cs_bid_pack_mismatch",
      payment_status: "paid",
      payment_intent: "pi_bid_pack_mismatch",
      customer_email: @user.email_address,
      metadata: OpenStruct.new(bid_pack_id: @bid_pack.id, user_id: @user.id),
      amount_total: 999,
      currency: "usd"
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/success",
          params: { session_id: "cs_bid_pack_mismatch", bid_pack_id: other_pack.id },
          headers: auth_headers(@user, @session_token)
    end

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "bid_pack_mismatch", body.dig("error", "code").to_s
    assert_match(/bid pack mismatch/i, body.dig("error", "message"))
    assert_equal 0, @user.reload.bid_credits
    assert_nil Purchase.find_by(stripe_checkout_session_id: "cs_bid_pack_mismatch")
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
