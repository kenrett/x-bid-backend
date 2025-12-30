require "test_helper"
require "ostruct"

class MoneyLoopPurchaseFlowTest < ActionDispatch::IntegrationTest
  FakeCheckoutCreateSession = Struct.new(:client_secret, keyword_init: true)
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

  test "close-the-loop flow creates purchase, grants credits, persists receipt when available, and is idempotent" do
    user = create_actor(role: :user)
    bid_pack = BidPack.create!(name: "Starter", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test pack", active: true)

    checkout_session_id = "cs_money_loop"
    payment_intent_id = "pi_money_loop"
    receipt_url = "https://stripe.example/receipts/rcpt_123"

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(client_secret: "cs_secret_123") }) do
      post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers_for(user)
    end

    assert_response :success
    assert JSON.parse(response.body).key?("clientSecret")

    checkout_session = FakeCheckoutSession.new(
      id: checkout_session_id,
      payment_status: "paid",
      payment_intent: payment_intent_id,
      customer_email: user.email_address,
      metadata: OpenStruct.new(bid_pack_id: bid_pack.id, user_id: user.id),
      amount_total: 999,
      currency: "usd"
    )

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :available, receipt_url, "ch_123" ] }) do
      Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
        assert_difference("Purchase.count", 1) do
          assert_difference("CreditTransaction.count", 1) do
            assert_difference("MoneyEvent.count", 1) do
              get "/api/v1/checkout/success", params: { session_id: checkout_session_id }, headers: auth_headers_for(user)
            end
          end
        end
      end
    end

    assert_response :success
    body1 = JSON.parse(response.body)
    assert_equal "success", body1["status"]
    assert_equal false, body1["idempotent"]
    assert_equal bid_pack.bids, body1["updated_bid_credits"]
    assert body1["purchaseId"].present?

    purchase = Purchase.find(body1["purchaseId"])
    assert_equal user.id, purchase.user_id
    assert_equal bid_pack.id, purchase.bid_pack_id
    assert_equal "completed", purchase.status
    assert_equal 999, purchase.amount_cents
    assert_equal "usd", purchase.currency
    assert_equal checkout_session_id, purchase.stripe_checkout_session_id
    assert_equal payment_intent_id, purchase.stripe_payment_intent_id
    assert_equal "available", purchase.receipt_status
    assert_equal receipt_url, purchase.receipt_url
    assert_equal "ch_123", purchase.stripe_charge_id

    credit = CreditTransaction.find_by!(purchase_id: purchase.id, reason: "bid_pack_purchase")
    assert_equal "grant", credit.kind
    assert_equal bid_pack.bids, credit.amount
    assert_equal "purchase:#{purchase.id}:grant", credit.idempotency_key
    assert_equal credit.id, purchase.reload.ledger_grant_credit_transaction_id

    event = MoneyEvent.find_by!(event_type: "purchase", source_type: "StripePaymentIntent", source_id: payment_intent_id)
    assert_equal 999, event.amount_cents
    assert_equal "usd", event.currency
    assert_equal purchase.id, event.metadata["purchase_id"]

    get "/api/v1/me/purchases/#{purchase.id}", headers: auth_headers_for(user)
    assert_response :success
    purchase_body = JSON.parse(response.body)
    assert_equal purchase.id, purchase_body["id"]
    assert_equal "completed", purchase_body["payment_status"]
    assert_equal "completed", purchase_body["status"]
    assert_equal bid_pack.bids, purchase_body["credits_added"]
    assert_equal credit.id, purchase_body["ledger_grant_entry_id"]
    assert_equal "available", purchase_body["receipt_status"]
    assert_equal receipt_url, purchase_body["receipt_url"]
    assert_nil purchase_body.dig("bid_pack", "sku")

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :available, receipt_url, "ch_123" ] }) do
      Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
        assert_no_difference("Purchase.count") do
          assert_no_difference("CreditTransaction.count") do
            assert_no_difference("MoneyEvent.count") do
              get "/api/v1/checkout/success", params: { session_id: checkout_session_id }, headers: auth_headers_for(user)
            end
          end
        end
      end
    end

    assert_response :success
    body2 = JSON.parse(response.body)
    assert_equal "success", body2["status"]
    assert_equal true, body2["idempotent"]
    assert_equal purchase.id, body2["purchaseId"]
    assert_equal bid_pack.bids, user.reload.bid_credits
  end

  test "receipt link is returned only when available" do
    user = create_actor(role: :user)
    bid_pack = BidPack.create!(name: "No Receipt Pack", bids: 5, price: BigDecimal("4.99"), highlight: false, description: "test pack", active: true)

    checkout_session = FakeCheckoutSession.new(
      id: "cs_no_receipt",
      payment_status: "paid",
      payment_intent: "pi_no_receipt",
      customer_email: user.email_address,
      metadata: OpenStruct.new(bid_pack_id: bid_pack.id, user_id: user.id),
      amount_total: 499,
      currency: "usd"
    )

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :unavailable, nil, "ch_no_receipt" ] }) do
      Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
        get "/api/v1/checkout/success", params: { session_id: "cs_no_receipt" }, headers: auth_headers_for(user)
      end
    end

    assert_response :success
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_no_receipt")
    assert_equal "unavailable", purchase.receipt_status
    assert_nil purchase.receipt_url

    get "/api/v1/me/purchases/#{purchase.id}", headers: auth_headers_for(user)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "unavailable", body["receipt_status"]
    assert_nil body["receipt_url"]
  end
end
