require "test_helper"

class BidTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "bidder@example.com", password: "password", role: :user)
    @auction = Auction.create!(
      title: "Test Auction",
      description: "A test auction.",
      start_date: 1.day.ago,
      current_price: 10.00,
      status: :active
    )
  end

  test "should be valid when amount is greater than auction current_price" do
    bid = Bid.new(user: @user, auction: @auction, amount: 10.01)
    assert bid.valid?
  end

  test "should be invalid when amount is equal to auction current_price" do
    bid = Bid.new(user: @user, auction: @auction, amount: 10.00)
    refute bid.valid?
    assert_not_nil bid.errors[:amount]
    assert_includes bid.errors[:amount], "must be greater than the auction's current price"
  end
end
