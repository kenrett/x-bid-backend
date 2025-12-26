require "test_helper"

class CreditsDebitTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "debit@example.com", password: "password", role: :user, bid_credits: 1)
    @auction = Auction.create!(
      title: "Debit Auction",
      description: "Test",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active
    )
  end

  test "debit is idempotent by key and keeps cached balance correct" do
    key = "debit-1"

    LockOrder.with_user_then_auction(user: @user, auction: @auction) do
      Credits::Debit.for_bid!(user: @user, auction: @auction, idempotency_key: key, locked: true)
      Credits::Debit.for_bid!(user: @user, auction: @auction, idempotency_key: key, locked: true)
    end

    assert_equal 1, CreditTransaction.where(idempotency_key: key).count
    debit = CreditTransaction.find_by!(idempotency_key: key)
    assert_equal "debit", debit.kind
    assert_equal @auction.id, debit.auction_id
    assert_equal 0, Credits::Balance.for_user(@user.reload)
    assert_equal 0, @user.reload.bid_credits
  end

  test "debit raises on insufficient credits" do
    @user.update!(bid_credits: 0)

    assert_raises(Credits::Debit::InsufficientCreditsError) do
      LockOrder.with_user_then_auction(user: @user, auction: @auction) do
        Credits::Debit.for_bid!(user: @user, auction: @auction, idempotency_key: "debit-insufficient", locked: true)
      end
    end
  end
end
