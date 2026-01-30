require "test_helper"
require "ostruct"
require "stripe"

class PurchaseReceiptBackfillJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 9.99, active: true)
  end

  test "updates receipt_url and marks available when found" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_1",
      receipt_status: :pending,
      status: "applied",
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) {
      assert_equal "pi_1", payment_intent_id
      [ :available, "https://stripe.com/receipt/1", "ch_1" ]
    }) do
      PurchaseReceiptBackfillJob.perform_now
    end

    purchase.reload
    assert_equal "available", purchase.receipt_status
    assert_equal "https://stripe.com/receipt/1", purchase.receipt_url
    assert_equal "ch_1", purchase.stripe_charge_id
  end

  test "marks unavailable when Stripe responds but no receipt exists" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_2",
      receipt_status: :pending,
      status: "applied",
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) {
      assert_equal "pi_2", payment_intent_id
      [ :unavailable, nil, "ch_2" ]
    }) do
      PurchaseReceiptBackfillJob.perform_now
    end

    purchase.reload
    assert_equal "unavailable", purchase.receipt_status
    assert_nil purchase.receipt_url
    assert_equal "ch_2", purchase.stripe_charge_id
  end

  test "keeps pending on Stripe error" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: "pi_3",
      receipt_status: :pending,
      status: "applied",
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) {
      assert_equal "pi_3", payment_intent_id
      raise Stripe::StripeError, "timeout"
    }) do
      PurchaseReceiptBackfillJob.perform_now
    end

    purchase.reload
    assert_equal "pending", purchase.receipt_status
    assert_nil purchase.receipt_url
  end
end
