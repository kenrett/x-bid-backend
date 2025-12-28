require "test_helper"

class MoneyEventsAdminHistoryQueryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "ledger@example.com", password: "password", role: :user)
    @auction = Auction.create!(
      title: "Test Auction",
      description: "A test auction.",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active
    )
    @bid = Bid.create!(user: @user, auction: @auction, amount: 10.01)
  end

  test "order is deterministic" do
    t = Time.current
    e1 = MoneyEvent.create!(user: @user, event_type: :purchase, amount_cents: 500, currency: "usd", source_type: "StripePaymentIntent", source_id: "pi_1", occurred_at: t)
    e2 = MoneyEvent.create!(user: @user, event_type: :bid_spent, amount_cents: -1, currency: "usd", source: @bid, occurred_at: t)
    e3 = MoneyEvent.create!(user: @user, event_type: :refund, amount_cents: -100, currency: "usd", source_type: "StripePaymentIntent", source_id: "pi_1", occurred_at: t + 1.second)

    result = MoneyEvents::Queries::AdminHistory.call(params: { user_id: @user.id })

    assert_equal [ e1.id, e2.id, e3.id ], result.records.map { |r| r.money_event.id }
  end

  test "missing sources do not break response" do
    MoneyEvent.create!(user: @user, event_type: :bid_spent, amount_cents: -1, currency: "usd", source_type: "Bid", source_id: "999999", occurred_at: Time.current)
    MoneyEvent.create!(user: @user, event_type: :purchase, amount_cents: 500, currency: "usd", source_type: "StripePaymentIntent", source_id: "pi_missing", occurred_at: Time.current)

    result = MoneyEvents::Queries::AdminHistory.call(params: { user_id: @user.id })

    assert_equal 2, result.records.size
    assert_nil result.records.first.source
    assert_nil result.records.second.source
  end

  test "includes source objects when present" do
    event = MoneyEvent.create!(user: @user, event_type: :bid_spent, amount_cents: -1, currency: "usd", source: @bid, occurred_at: Time.current)

    result = MoneyEvents::Queries::AdminHistory.call(params: { user_id: @user.id })

    row = result.records.find { |r| r.money_event.id == event.id }
    assert_not_nil row
    assert_instance_of Bid, row.source
    assert_equal @bid.id, row.source.id
  end
end
