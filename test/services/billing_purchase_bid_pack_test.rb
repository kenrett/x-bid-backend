require "test_helper"

class BillingPurchaseBidPackTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", bid_credits: 0)
    @pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)
  end

  test "increments bid credits on purchase" do
    result = Billing::PurchaseBidPack.new(user: @user, bid_pack: @pack).call

    assert result.success?
    assert_equal "Bid pack purchased successfully!", result.message
    assert_equal 10, @user.reload.bid_credits
  end
end
