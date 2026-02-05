require "test_helper"

class CreditsReconcileBalancesTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "reconcile@example.com", password: "password", role: :user, bid_credits: 5)
    CreditTransaction.create!(
      user: @user,
      kind: :grant,
      amount: 10,
      reason: "bonus",
      idempotency_key: "reconcile:grant"
    )
    CreditTransaction.create!(
      user: @user,
      kind: :debit,
      amount: -2,
      reason: "bid_placed",
      idempotency_key: "reconcile:debit"
    )
  end

  test "reconcile detects drift without fixing" do
    stats = Credits::ReconcileBalances.call!(fix: false, scope: User.where(id: @user.id))

    assert_equal 1, stats[:checked]
    assert_equal 1, stats[:drifted]
    assert_equal 0, stats[:fixed]
    assert_equal 5, @user.reload.bid_credits
  end

  test "reconcile can fix drift" do
    stats = Credits::ReconcileBalances.call!(fix: true, scope: User.where(id: @user.id))

    assert_equal 1, stats[:checked]
    assert_equal 1, stats[:drifted]
    assert_equal 1, stats[:fixed]
    assert_equal 8, @user.reload.bid_credits
  end
end
