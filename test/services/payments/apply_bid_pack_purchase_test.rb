require "test_helper"

class PaymentsApplyBidPackPurchaseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)
  end

  test "calling twice does not double-credit and creates purchase once" do
    result1 = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_123",
      stripe_payment_intent_id: "pi_123",
      stripe_event_id: "evt_123",
      amount_cents: 100,
      currency: "usd",
      source: "test"
    )
    result2 = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: "cs_123",
      stripe_payment_intent_id: "pi_123",
      stripe_event_id: "evt_123",
      amount_cents: 100,
      currency: "usd",
      source: "test"
    )

    assert result1.ok?
    assert_equal false, result1.idempotent
    assert result2.ok?
    assert_equal true, result2.idempotent

    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_123")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 10, @user.reload.bid_credits
  end

  test "repairs when purchase exists but credit grant is missing" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_payment_intent_id: "pi_456",
      status: "completed"
    )

    assert_equal 0, CreditTransaction.where(purchase_id: purchase.id).count

    result = Payments::ApplyBidPackPurchase.call!(
      user: @user,
      bid_pack: @bid_pack,
      stripe_checkout_session_id: nil,
      stripe_payment_intent_id: "pi_456",
      stripe_event_id: nil,
      amount_cents: 100,
      currency: "usd",
      source: "test"
    )

    assert result.ok?
    assert_equal false, result.idempotent
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_456").count
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 10, @user.reload.bid_credits
  end
end
