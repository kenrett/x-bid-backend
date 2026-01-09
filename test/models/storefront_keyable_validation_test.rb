require "test_helper"
require "securerandom"

class StorefrontKeyableValidationTest < ActiveSupport::TestCase
  test "storefront_key rejects unknown keys on core models" do
    user = create_actor(role: :user)
    bid_pack = BidPack.create!(name: "Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true, storefront_key: "main")
    auction = Auction.create!(
      title: "Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active,
      storefront_key: "main"
    )

    records = [
      Auction.new(
        title: "Bad",
        description: "Desc",
        start_date: 1.minute.ago,
        end_time: 1.hour.from_now,
        current_price: BigDecimal("1.00"),
        status: :active,
        storefront_key: "bogus"
      ),
      Bid.new(user: user, auction: auction, amount: BigDecimal("2.00"), storefront_key: "bogus"),
      Purchase.new(user: user, bid_pack: bid_pack, amount_cents: 100, currency: "usd", status: "completed", storefront_key: "bogus"),
      CreditTransaction.new(user: user, kind: :grant, amount: 1, reason: "test", idempotency_key: "k-#{SecureRandom.hex(6)}", storefront_key: "bogus"),
      MoneyEvent.new(user: user, event_type: :purchase, amount_cents: 100, currency: "usd", occurred_at: Time.current, storefront_key: "bogus"),
      AuctionSettlement.new(auction: auction, ended_at: Time.current, final_price: BigDecimal("0.00"), currency: "usd", status: :no_winner, storefront_key: "bogus"),
      BidPack.new(name: "Bad Pack", bids: 1, price: BigDecimal("1.00"), storefront_key: "bogus"),
      AuditLog.new(action: "test.action", storefront_key: "bogus")
    ]

    records.each do |record|
      refute record.valid?, "Expected #{record.class} with invalid storefront_key to be invalid"
      assert_includes record.errors[:storefront_key], "is not included in the list"
    end
  end
end
