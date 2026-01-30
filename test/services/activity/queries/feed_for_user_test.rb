require "test_helper"
require "securerandom"

class ActivityQueriesFeedForUserTest < ActiveSupport::TestCase
  test "includes purchase_completed items for the user with expected payload" do
    user = User.create!(name: "User", email_address: "activity_purchases@example.com", password: "password", bid_credits: 0)
    other_user = User.create!(name: "Other", email_address: "activity_purchases_other@example.com", password: "password", bid_credits: 0)

    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 100, price: 1.0, active: true)

    stripe_payment_intent_id = "pi_activity_#{SecureRandom.hex(8)}"
    other_stripe_payment_intent_id = "pi_activity_other_#{SecureRandom.hex(8)}"

    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 123,
      currency: "usd",
      stripe_payment_intent_id: stripe_payment_intent_id,
      receipt_status: :available,
      receipt_url: "https://stripe.example/receipts/rcpt_1",
      stripe_charge_id: "ch_1"
    )
    MoneyEvent.create!(
      user: user,
      event_type: :purchase,
      amount_cents: purchase.amount_cents,
      currency: purchase.currency,
      source_type: "StripePaymentIntent",
      source_id: stripe_payment_intent_id,
      occurred_at: 2.days.ago,
      metadata: { purchase_id: purchase.id }
    )

    other_purchase = Purchase.create!(
      user: other_user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: other_stripe_payment_intent_id
    )

    result = Activity::Queries::FeedForUser.call(user: user, params: { page: 1, per_page: 50 })
    purchase_item = result.records.find { |item| item[:type] == "purchase_completed" }
    assert purchase_item.present?

    assert purchase_item[:occurred_at].present?
    assert_equal purchase_item[:occurred_at], purchase_item[:created_at]
    assert_nil purchase_item[:auction]

    data = purchase_item.fetch(:data)
    assert_equal purchase.id, data.fetch(:purchase_id)
    assert_equal bid_pack.id, data.fetch(:bid_pack_id)
    assert_equal bid_pack.name, data.fetch(:bid_pack_name)
    assert_equal bid_pack.bids, data.fetch(:credits_added)
    assert_equal 123, data.fetch(:amount_cents)
    assert_equal "usd", data.fetch(:currency)
    assert_equal "applied", data.fetch(:payment_status)
    assert_equal "available", data.fetch(:receipt_status)
    assert_equal "https://stripe.example/receipts/rcpt_1", data.fetch(:receipt_url)
    assert_equal stripe_payment_intent_id, data.fetch(:stripe_payment_intent_id)
    assert_equal "ch_1", data.fetch(:stripe_charge_id)

    purchase_items = result.records.select { |item| item[:type] == "purchase_completed" }
    assert_equal [ purchase.id ], purchase_items.map { |item| item.dig(:data, :purchase_id) }
  end

  test "orders purchase_completed by occurred_at (money event) across types" do
    user = User.create!(name: "User", email_address: "activity_purchases_order@example.com", password: "password", bid_credits: 0)
    bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 100, price: 1.0, active: true)

    auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    bid = Bid.create!(user: user, auction: auction, amount: BigDecimal("2.00"), created_at: 3.days.ago)

    stripe_payment_intent_id = "pi_activity_order_#{SecureRandom.hex(8)}"
    purchase = Purchase.create!(
      user: user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 123,
      currency: "usd",
      stripe_payment_intent_id: stripe_payment_intent_id,
      created_at: 10.days.ago
    )
    MoneyEvent.create!(
      user: user,
      event_type: :purchase,
      amount_cents: purchase.amount_cents,
      currency: purchase.currency,
      source_type: "StripePaymentIntent",
      source_id: stripe_payment_intent_id,
      occurred_at: 2.days.ago,
      metadata: { purchase_id: purchase.id }
    )

    watch = AuctionWatch.create!(user: user, auction: auction, created_at: 1.day.ago)

    result = Activity::Queries::FeedForUser.call(user: user, params: { page: 1, per_page: 50 })
    types = result.records.map { |item| item[:type] }
    assert_equal [ "auction_watched", "purchase_completed", "bid_placed" ], types
  end
end
