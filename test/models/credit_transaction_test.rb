require "test_helper"
require "securerandom"

class CreditTransactionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "ledger@example.com", password: "password", role: :user)
  end

  def build_transaction(attrs = {})
    default_attrs = {
      user: @user,
      kind: :grant,
      amount: 10,
      reason: "signup bonus",
      idempotency_key: SecureRandom.uuid
    }

    CreditTransaction.new(default_attrs.merge(attrs))
  end

  test "enforces unique idempotency_key" do
    CreditTransaction.create!(user: @user, kind: :grant, amount: 10, reason: "initial", idempotency_key: "dupe")

    duplicate = build_transaction(idempotency_key: "dupe")

    refute duplicate.valid?
    assert_includes duplicate.errors[:idempotency_key], "has already been taken"
  end

  test "is append-only" do
    entry = CreditTransaction.create!(user: @user, kind: :grant, amount: 10, reason: "initial", idempotency_key: "immutable")

    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(amount: 20) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.destroy! }
  end

  test "requires a nonzero integer amount and reason" do
    entry = build_transaction(amount: 0, reason: nil)

    refute entry.valid?
    assert_includes entry.errors[:amount], "must be other than 0"
    assert_includes entry.errors[:reason], "can't be blank"
  end
end
