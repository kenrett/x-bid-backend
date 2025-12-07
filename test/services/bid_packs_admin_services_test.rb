require "test_helper"

class BidPacksAdminServicesTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin2@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "admin upsert creates a bid pack" do
    attrs = { name: "Gold", description: "Desc", bids: 100, price: 10.0, active: true }
    logged = []

    assert_difference -> { BidPack.count }, +1 do
      result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
        Admin::BidPacks::Upsert.new(actor: @admin, attrs: attrs).call
      end

      assert_nil result.error
      assert_equal "Gold", result.record.name
    end

    assert_equal "admin.bid_packs.upsert", logged.last[:event]
    assert_equal true, logged.last[:success]
    assert_equal @admin.id, logged.last[:admin_id]
  end

  test "admin upsert updates a bid pack" do
    pack = BidPack.create!(name: "Silver", description: "Desc", bids: 50, price: 5.0, active: true)

    result = Admin::BidPacks::Upsert.new(actor: @admin, bid_pack: pack, attrs: { price: 6.0 }).call

    assert_nil result.error
    assert_equal 6.0, pack.reload.price
  end

  test "admin upsert returns a failed result when validation fails" do
    attrs = { name: "", description: "Desc", bids: 0, price: -1.0 }

    assert_no_difference -> { BidPack.count } do
      result = Admin::BidPacks::Upsert.new(actor: @admin, attrs: attrs).call

      refute result.ok?
      assert_equal :invalid_bid_pack, result.code
      assert_match(/Name can't be blank/, result.error)
    end
  end

  test "non-admin upsert is forbidden" do
    attrs = { name: "Forbidden", description: "Desc", bids: 10, price: 1.0, active: true }

    result = Admin::BidPacks::Upsert.new(actor: @user, attrs: attrs).call

    refute result.ok?
    assert_equal :forbidden, result.code
  end

  test "retire errors when already retired" do
    pack = BidPack.create!(name: "Bronze", description: "Desc", bids: 10, price: 1.0, active: false, status: :retired)
    logged = []

    result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
      Admin::BidPacks::Retire.new(actor: @admin, bid_pack: pack).call
    end

    assert_equal "Bid pack already retired", result.error
    assert_equal false, logged.last[:success]
  end

  test "retire sets status to retired and logs audit" do
    pack = BidPack.create!(name: "Platinum", description: "Desc", bids: 200, price: 20.0, active: true)
    logged = []

    assert_difference -> { AuditLog.count }, +1 do
      result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
        Admin::BidPacks::Retire.new(actor: @admin, bid_pack: pack).call
      end

      assert_nil result.error
    end

    pack.reload
    assert_equal "retired", pack.status
    assert_equal false, pack.active
    assert_equal "admin.bid_packs.retire", logged.last[:event]
    assert_equal true, logged.last[:success]
  end

  test "non-admin retire is forbidden" do
    pack = BidPack.create!(name: "Forbidden Retire", description: "Desc", bids: 10, price: 1.0, active: true)

    result = Admin::BidPacks::Retire.new(actor: @user, bid_pack: pack).call

    refute result.ok?
    assert_equal :forbidden, result.code
    assert_equal "active", pack.reload.status
  end
end
