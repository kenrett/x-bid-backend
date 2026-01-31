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

    ActivityEvent.create!(
      user_id: user.id,
      event_type: "purchase_completed",
      occurred_at: 2.days.ago,
      data: {
        purchase_id: purchase.id,
        bid_pack_id: bid_pack.id,
        bid_pack_name: bid_pack.name,
        credits_added: bid_pack.bids,
        amount_cents: purchase.amount_cents,
        currency: purchase.currency,
        payment_status: purchase.status,
        receipt_url: purchase.receipt_url,
        receipt_status: purchase.receipt_status,
        stripe_payment_intent_id: purchase.stripe_payment_intent_id,
        stripe_charge_id: purchase.stripe_charge_id
      }
    )

    other_purchase = Purchase.create!(
      user: other_user,
      bid_pack: bid_pack,
      status: "applied",
      amount_cents: 999,
      currency: "usd",
      stripe_payment_intent_id: other_stripe_payment_intent_id
    )

    ActivityEvent.create!(
      user_id: other_user.id,
      event_type: "purchase_completed",
      occurred_at: 1.day.ago,
      data: {
        purchase_id: other_purchase.id,
        bid_pack_id: bid_pack.id,
        bid_pack_name: bid_pack.name,
        credits_added: bid_pack.bids,
        amount_cents: other_purchase.amount_cents,
        currency: other_purchase.currency,
        payment_status: other_purchase.status,
        receipt_url: other_purchase.receipt_url,
        receipt_status: other_purchase.receipt_status,
        stripe_payment_intent_id: other_purchase.stripe_payment_intent_id,
        stripe_charge_id: other_purchase.stripe_charge_id
      }
    )

    result = Activity::Queries::FeedForUser.call(user: user, params: { page: 1, per_page: 50 })
    purchase_item = result.records.find { |item| item[:type] == "purchase_completed" }
    assert purchase_item.present?

    assert purchase_item[:occurred_at].present?
    assert_equal purchase_item[:occurred_at], purchase_item[:created_at]
    assert_nil purchase_item[:auction]

    data = purchase_item.fetch(:data)
    assert_equal purchase.id, data.fetch("purchase_id")
    assert_equal bid_pack.id, data.fetch("bid_pack_id")
    assert_equal bid_pack.name, data.fetch("bid_pack_name")
    assert_equal bid_pack.bids, data.fetch("credits_added")
    assert_equal 123, data.fetch("amount_cents")
    assert_equal "usd", data.fetch("currency")
    assert_equal "applied", data.fetch("payment_status")
    assert_equal "available", data.fetch("receipt_status")
    assert_equal "https://stripe.example/receipts/rcpt_1", data.fetch("receipt_url")
    assert_equal stripe_payment_intent_id, data.fetch("stripe_payment_intent_id")
    assert_equal "ch_1", data.fetch("stripe_charge_id")

    purchase_items = result.records.select { |item| item[:type] == "purchase_completed" }
    assert_equal [ purchase.id ], purchase_items.map { |item| item.dig(:data, "purchase_id") }
  end

  test "orders mixed event types by occurred_at and id" do
    user = User.create!(name: "User", email_address: "activity_order@example.com", password: "password", bid_credits: 0)

    auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )

    t0 = 3.days.ago
    t1 = 2.days.ago
    t2 = 1.day.ago

    ActivityEvent.create!(
      user_id: user.id,
      event_type: "bid_placed",
      occurred_at: t0,
      data: { auction_id: auction.id, bid_id: 1, amount: "2.0" }
    )
    ActivityEvent.create!(
      user_id: user.id,
      event_type: "purchase_completed",
      occurred_at: t1,
      data: { purchase_id: 1 }
    )
    ActivityEvent.create!(
      user_id: user.id,
      event_type: "auction_watched",
      occurred_at: t2,
      data: { auction_id: auction.id, watch_id: 2 }
    )

    result = Activity::Queries::FeedForUser.call(user: user, params: { page: 1, per_page: 50 })
    assert_equal [ "auction_watched", "purchase_completed", "bid_placed" ], result.records.map { |item| item[:type] }
  end

  test "paginates with cursor without duplicates or gaps" do
    user = User.create!(name: "User", email_address: "activity_cursor@example.com", password: "password", bid_credits: 0)

    base_time = Time.current.change(usec: 0)
    events = 5.times.map do |idx|
      ActivityEvent.create!(
        user_id: user.id,
        event_type: "bid_placed",
        occurred_at: base_time - (idx / 2).minutes,
        data: { bid_id: idx + 1 }
      )
    end

    first_page = Activity::Queries::FeedForUser.call(user: user, params: { per_page: 2 })
    cursor = first_page.meta.fetch(:next_cursor)
    second_page = Activity::Queries::FeedForUser.call(user: user, params: { per_page: 2, cursor: cursor })

    first_ids = first_page.records.map { |item| item.dig(:data, "bid_id") }
    second_ids = second_page.records.map { |item| item.dig(:data, "bid_id") }

    assert_equal 2, first_ids.length
    assert_equal 2, second_ids.length
    assert (first_ids & second_ids).empty?
    assert_equal events.sort_by { |e| [ e.occurred_at, e.id ] }.reverse.map { |e| e.data["bid_id"] }[0, 4], first_ids + second_ids
  end

  test "does not instantiate large histories when paging" do
    user = User.create!(name: "User", email_address: "activity_perf@example.com", password: "password", bid_credits: 0)

    now = Time.current
    rows = 10_000.times.map do |idx|
      {
        user_id: user.id,
        event_type: "bid_placed",
        occurred_at: now - idx.seconds,
        data: { bid_id: idx + 1 },
        created_at: now,
        updated_at: now
      }
    end
    ActivityEvent.insert_all(rows)

    instantiated = Hash.new(0)
    subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
      class_name = payload[:class_name]
      instantiated[class_name] += payload[:record_count].to_i if class_name
    end

    result = nil
    begin
      result = Activity::Queries::FeedForUser.call(user: user, params: { per_page: 5 })
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal 5, result.records.length
    assert_operator instantiated.fetch("ActivityEvent", 0), :<=, 6
  end
end
