require "test_helper"

class BidPacksAdminServicesTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin2@example.com", password: "password", role: :admin, bid_credits: 0)
  end

  test "admin upsert creates a bid pack" do
    attrs = { name: "Gold", description: "Desc", bids: 100, price: 10.0, active: true }

    assert_difference -> { BidPack.count }, +1 do
      result = BidPacks::AdminUpsert.new(actor: @admin, attrs: attrs).call
    assert_nil result.error
    assert_equal "Gold", result.record.name
    end
  end

  test "admin upsert updates a bid pack" do
    pack = BidPack.create!(name: "Silver", description: "Desc", bids: 50, price: 5.0, active: true)

    result = BidPacks::AdminUpsert.new(actor: @admin, bid_pack: pack, attrs: { price: 6.0 }).call

    assert_nil result.error
    assert_equal 6.0, pack.reload.price
  end

  test "retire errors when already retired" do
    pack = BidPack.create!(name: "Bronze", description: "Desc", bids: 10, price: 1.0, active: false, status: :retired)

    result = BidPacks::Retire.new(actor: @admin, bid_pack: pack).call

    assert_equal "Bid pack already retired", result.error
  end

  test "retire sets status to retired and logs audit" do
    pack = BidPack.create!(name: "Platinum", description: "Desc", bids: 200, price: 20.0, active: true)

    assert_difference -> { AuditLog.count }, +1 do
      result = BidPacks::Retire.new(actor: @admin, bid_pack: pack).call
    assert_nil result.error
    end

    pack.reload
    assert_equal "retired", pack.status
    assert_equal false, pack.active
  end
end
