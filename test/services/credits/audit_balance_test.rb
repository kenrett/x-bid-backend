require "test_helper"

class CreditsAuditBalanceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "audit@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "audit reports cached and derived balances and drift" do
    Credits::Apply.apply!(user: @user, reason: "seed", amount: 2, idempotency_key: "audit-seed-1")

    audit = Credits::AuditBalance.call(user: @user.reload)
    assert_equal true, audit[:matches]
    assert_equal 2, audit[:cached]
    assert_equal 2, audit[:derived]

    @user.update_columns(bid_credits: 3)
    audit_after_drift = Credits::AuditBalance.call(user: @user.reload)
    assert_equal false, audit_after_drift[:matches]
    assert_equal 3, audit_after_drift[:cached]
    assert_equal 2, audit_after_drift[:derived]
  end
end
