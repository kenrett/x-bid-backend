require "test_helper"

class Credits::LedgerWriterTest < ActiveSupport::TestCase
  setup do
    Current.reset
  end

  teardown do
    CreditTransaction.delete_all
    Current.reset
  end

  test "uses Current storefront_key when present" do
    user = create_actor(role: :user)
    Current.storefront_key = "afterdark"

    result = Credits::Ledger::Writer.write!(
      user: user,
      kind: :grant,
      amount: 5,
      reason: "ledger.grant",
      idempotency_key: "ledger.writer:test:1",
      metadata: { source: "test" }
    )

    assert_equal "afterdark", result.transaction.storefront_key
    assert result.created?
  end

  test "warns and defaults to main when storefront context is missing" do
    user = create_actor(role: :user)
    logs = []
    AppLogger.stub(:log, ->(event:, **context) { logs << [ event, context ]; nil }) do
      result = Credits::Ledger::Writer.write!(
        user: user,
        kind: :grant,
        amount: 10,
        reason: "ledger.backfill",
        idempotency_key: "ledger.writer:test:2",
        metadata: {}
      )

      assert_equal "main", result.transaction.storefront_key
      assert logs.any? { |event, _| event == "ledger.write.missing_storefront" }
    end
  end

  test "does not create duplicate entries for the same idempotency key" do
    user = create_actor(role: :user)
    Current.storefront_key = "marketplace"
    key = "ledger.writer:duplicate:#{user.id}"

    first = Credits::Ledger::Writer.write!(
      user: user,
      kind: :grant,
      amount: 7,
      reason: "ledger.duplicate",
      idempotency_key: key,
      metadata: {}
    )
    second = Credits::Ledger::Writer.write!(
      user: user,
      kind: :grant,
      amount: 7,
      reason: "ledger.duplicate",
      idempotency_key: key,
      metadata: {}
    )

    assert second.existing?
    assert_equal first.transaction.id, second.transaction.id
    assert_equal 1, CreditTransaction.where(idempotency_key: key).count
  end
end
