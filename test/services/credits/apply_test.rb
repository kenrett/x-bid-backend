require "test_helper"

class CreditsApplyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "apply@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "apply is idempotent by key and keeps cached balance correct" do
    key = "apply-1"

    Credits::Apply.apply!(user: @user, reason: "bonus", amount: 5, idempotency_key: key)
    Credits::Apply.apply!(user: @user, reason: "bonus", amount: 5, idempotency_key: key)

    assert_equal 1, CreditTransaction.where(idempotency_key: key).count
    assert_equal 5, Credits::Balance.for_user(@user)
    assert_equal 5, @user.reload.bid_credits
  end
end
