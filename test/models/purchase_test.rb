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
      status: "applied",
      receipt_url: nil
    )

    assert purchase.valid?
    assert_equal "pending", purchase.receipt_status
  end

  test "status must be present and canonical" do
    purchase = Purchase.new(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      status: "completed"
    )

    refute purchase.valid?
    assert_includes purchase.errors[:status], "is not included in the list"

    purchase.status = nil
    refute purchase.valid?
    assert_includes purchase.errors[:status], "can't be blank"
  end
end
