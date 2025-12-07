require "test_helper"

class BidPacksAdminServicesTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin2@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "admin upsert creates a bid pack" do
    attrs = { name: "Gold", description: "Desc", bids: 100, price: 10.0, active: true }

    assert_difference -> { BidPack.count }, +1 do
    result = Admin::BidPacks::Upsert.new(actor: @admin, attrs: attrs).call
    assert_nil result.error
    assert_equal "Gold", result.record.name
    end
  end

  test "admin upsert updates a bid pack" do
    pack = BidPack.create!(name: "Silver", description: "Desc", bids: 50, price: 5.0, active: true)

    result = Admin::BidPacks::Upsert.new(actor: @admin, bid_pack: pack, attrs: { price: 6.0 }).call

    assert_nil result.error
    assert_equal 6.0, pack.reload.price
  end

  test "non-admin upsert is forbidden" do
    attrs = { name: "Forbidden", description: "Desc", bids: 10, price: 1.0, active: true }

    result = Admin::BidPacks::Upsert.new(actor: @user, attrs: attrs).call

    refute result.ok?
    assert_equal :forbidden, result.code
  end

  test "retire errors when already retired" do
    pack = BidPack.create!(name: "Bronze", description: "Desc", bids: 10, price: 1.0, active: false, status: :retired)

    result = Admin::BidPacks::Retire.new(actor: @admin, bid_pack: pack).call

    assert_equal "Bid pack already retired", result.error
  end

  test "retire sets status to retired and logs audit" do
    pack = BidPack.create!(name: "Platinum", description: "Desc", bids: 200, price: 20.0, active: true)

    assert_difference -> { AuditLog.count }, +1 do
    result = Admin::BidPacks::Retire.new(actor: @admin, bid_pack: pack).call
    assert_nil result.error
    end

    pack.reload
    assert_equal "retired", pack.status
    assert_equal false, pack.active
  end

  test "non-admin retire is forbidden" do
    pack = BidPack.create!(name: "Forbidden Retire", description: "Desc", bids: 10, price: 1.0, active: true)

    result = Admin::BidPacks::Retire.new(actor: @user, bid_pack: pack).call

    refute result.ok?
    assert_equal :forbidden, result.code
    assert_equal "active", pack.reload.status
  end
end
