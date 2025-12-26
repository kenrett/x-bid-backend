require "test_helper"
require "securerandom"

class CreditsLedgerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "ledger@example.com", password: "password", role: :user)
  end

  test "ledger writes keep cached balance in sync" do
    Credits::Apply.apply!(user: @user, reason: "welcome bonus", amount: 5, idempotency_key: "welcome-1")

    derived = Credits::Balance.for_user(@user)
    assert_equal 5, derived
    assert_equal derived, @user.reload.bid_credits
  end

  test "rebuild fixes cached drift" do
    CreditTransaction.create!(user: @user, kind: :grant, amount: 3, reason: "manual", idempotency_key: "manual-1", metadata: {})
    @user.update!(bid_credits: 99)

    Credits::RebuildBalance.call!(user: @user)

    assert_equal 3, @user.reload.bid_credits
  end

  test "audit reports cache and derived balances" do
    CreditTransaction.create!(user: @user, kind: :grant, amount: 2, reason: "seed", idempotency_key: "seed-1", metadata: {})
    Credits::RebuildBalance.call!(user: @user)

    audit = Credits::AuditBalance.call(user: @user.reload)
    assert_equal true, audit[:matches]
    assert_equal @user.bid_credits, audit[:derived]

    @user.update_columns(bid_credits: audit[:derived] + 1)
    audit_after_drift = Credits::AuditBalance.call(user: @user.reload)
    assert_equal false, audit_after_drift[:matches]
    assert_equal audit[:derived], audit_after_drift[:derived]
  end
end
