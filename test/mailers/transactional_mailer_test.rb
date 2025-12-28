require "test_helper"

class TransactionalMailerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Buyer", email_address: "buyer@example.com", password: "password", role: :user)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 10, price: 1.0, active: true)
  end

  test "UI never renders broken receipt links" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      status: "completed",
      receipt_url: "https://example.com/receipt",
      receipt_status: :pending
    )

    mail = TransactionalMailer.purchase_receipt(purchase.id)
    refute_includes mail.html_part.body.to_s, "View Stripe receipt"
    refute_includes mail.text_part.body.to_s, "Stripe receipt:"

    purchase.update!(receipt_status: :available)
    mail = TransactionalMailer.purchase_receipt(purchase.id)
    assert_includes mail.html_part.body.to_s, "View Stripe receipt"
    assert_includes mail.text_part.body.to_s, "Stripe receipt: https://example.com/receipt"
  end
end
