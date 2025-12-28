require "test_helper"

class PurchaseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "buyer@example.com", password: "password", role: :user)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)
  end

  test "purchases without receipts are valid" do
    purchase = Purchase.new(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      status: "completed",
      receipt_url: nil
    )

    assert purchase.valid?
    assert_equal "pending", purchase.receipt_status
  end
end
