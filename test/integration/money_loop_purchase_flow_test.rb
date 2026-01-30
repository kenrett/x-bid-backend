require "test_helper"
require "ostruct"

class MoneyLoopPurchaseFlowTest < ActionDispatch::IntegrationTest
  FakeCheckoutCreateSession = Struct.new(:id, :client_secret, :payment_intent, keyword_init: true)

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

  test "checkout create persists purchase, webhook applies credits, and success is read-only" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)

    checkout_session_id = "cs_money_loop"
    payment_intent_id = "pi_money_loop"
    receipt_url = "https://stripe.example/receipts/rcpt_123"

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(id: checkout_session_id, client_secret: "cs_secret_123", payment_intent: payment_intent_id) }) do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end

    assert_response :success
    assert JSON.parse(response.body).key?("clientSecret")

    purchase = Purchase.find_by!(stripe_checkout_session_id: checkout_session_id)
    assert_equal "created", purchase.status

    get "/api/v1/checkout/success", params: { session_id: checkout_session_id }, headers: auth_headers_for(user)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_equal purchase.id, body["purchase_id"]

    payload = {
      id: "evt_cs_money_loop",
      type: "checkout.session.completed",
      data: {
        object: {
          id: checkout_session_id,
          payment_status: "paid",
          payment_intent: payment_intent_id,
          metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
          amount_total: 999,
          currency: "usd"
        }
      }
    }

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :available, receipt_url, "ch_123" ] }) do
      Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
    end

    purchase = Purchase.find_by!(stripe_checkout_session_id: checkout_session_id)
    assert_equal "applied", purchase.status
    assert_equal "available", purchase.receipt_status
    assert_equal receipt_url, purchase.receipt_url
    assert_equal bid_pack.bids, user.reload.bid_credits

    get "/api/v1/checkout/success", params: { session_id: checkout_session_id }, headers: auth_headers_for(user)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "applied", body["status"]
    assert_equal purchase.id, body["purchase_id"]
  end

  test "receipt link is returned only when available" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    bid_pack = BidPack.create!(name: "No Receipt Pack", bids: 5, price: BigDecimal("4.99"), highlight: false, description: "test pack", active: true)

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      amount_cents: 499,
      currency: "usd",
      stripe_checkout_session_id: "cs_no_receipt",
      stripe_payment_intent_id: "pi_no_receipt",
      status: "created"
    )

    payload = {
      id: "evt_cs_no_receipt",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_no_receipt",
          payment_status: "paid",
          payment_intent: "pi_no_receipt",
          metadata: { user_id: user.id, bid_pack_id: bid_pack.id, purchase_id: purchase.id },
          amount_total: 499,
          currency: "usd"
        }
      }
    }

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :unavailable, nil, "ch_no_receipt" ] }) do
      Stripe::WebhookEvents::Process.call(event: FakeStripeEvent.new(payload))
    end

    purchase.reload
    assert_equal "unavailable", purchase.receipt_status
    assert_nil purchase.receipt_url

    get "/api/v1/me/purchases/#{purchase.id}", headers: auth_headers_for(user)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "unavailable", body["receipt_status"]
    assert_nil body["receipt_url"]
  end
end
