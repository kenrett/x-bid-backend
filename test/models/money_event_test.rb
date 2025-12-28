require "test_helper"

class MoneyEventTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "money@example.com", password: "password", role: :user)
  end

  test "creating a MoneyEvent succeeds" do
    event = MoneyEvent.create!(
      user: @user,
      event_type: :purchase,
      amount_cents: 500,
      currency: "usd",
      occurred_at: Time.current
    )

    assert event.persisted?
  end

  test "is append-only" do
    event = MoneyEvent.create!(
      user: @user,
      event_type: :refund,
      amount_cents: -100,
      currency: "usd",
      occurred_at: Time.current
    )

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(amount_cents: 0) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
  end

  test "invalid event_type is rejected" do
    event = MoneyEvent.new(
      user: @user,
      event_type: "not_real",
      amount_cents: 100,
      currency: "usd",
      occurred_at: Time.current
    )

    refute event.valid?
    assert_includes event.errors[:event_type], "is not included in the list"
  end
end
