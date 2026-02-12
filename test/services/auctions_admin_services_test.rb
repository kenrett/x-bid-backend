require "test_helper"

class AuctionsAdminServicesTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin@example.com", password: "password", role: :admin, bid_credits: 0)
  end

  test "admin upsert creates an auction" do
    attrs = {
      title: "New Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active
    }

    assert_difference -> { Auction.count }, +1 do
    result = Admin::Auctions::Upsert.new(actor: @admin, attrs: attrs).call
    assert_nil result.error
    assert result.record.persisted?
    assert_equal "New Auction", result.record.title
    end
  end

  test "admin upsert updates an auction" do
    auction = Auction.create!(title: "Old", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :pending)
    attrs = { status: :active }

    result = Admin::Auctions::Upsert.new(actor: @admin, auction: auction, attrs: attrs).call

    assert_nil result.error
    assert_equal "active", auction.reload.status
  end

  test "admin upsert restores inactive auction to scheduled" do
    auction = Auction.create!(title: "Inactive", description: "Desc", start_date: 2.hours.from_now, end_time: 1.day.from_now, current_price: 1.0, status: :inactive)
    attrs = { status: :pending }

    result = Admin::Auctions::Upsert.new(actor: @admin, auction: auction, attrs: attrs).call

    assert result.ok?
    assert_equal "pending", auction.reload.status
  end

  test "admin upsert rejects inactive to active transition" do
    auction = Auction.create!(title: "Inactive", description: "Desc", start_date: 2.hours.from_now, end_time: 1.day.from_now, current_price: 1.0, status: :inactive)
    attrs = { status: :active }

    result = Admin::Auctions::Upsert.new(actor: @admin, auction: auction, attrs: attrs).call

    refute result.ok?
    assert_equal :invalid_state, result.code
    assert_match "inactive to active", result.error
    assert_equal "inactive", auction.reload.status
  end

  test "retire fails when bids exist" do
    auction = Auction.create!(title: "Bidded", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    bidder = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    Bid.create!(user: bidder, auction: auction, amount: 2.0)

    result = Admin::Auctions::Retire.new(actor: @admin, auction: auction).call

    assert_equal "Cannot retire an auction that has bids.", result.error
  end

  test "retire sets auction inactive and logs audit" do
    auction = Auction.create!(title: "Retire Me", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)

    assert_difference -> { AuditLog.count }, +1 do
    result = Admin::Auctions::Retire.new(actor: @admin, auction: auction).call
    assert_nil result.error
    end

    assert_equal "inactive", auction.reload.status
  end

  test "upsert rejects non-admin actor" do
    user = User.create!(name: "User", email_address: "user@example.com", password: "password", role: :user, bid_credits: 0)
    attrs = {
      title: "Unauthorized Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active
    }

    assert_no_difference -> { Auction.count } do
      result = Admin::Auctions::Upsert.new(actor: user, attrs: attrs).call
      refute result.success?
      assert_equal "Admin privileges required", result.error
      assert_equal :forbidden, result.code
    end
  end

  test "retire rejects non-admin actor" do
    auction = Auction.create!(title: "Retire Me", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    user = User.create!(name: "User", email_address: "user2@example.com", password: "password", role: :user, bid_credits: 0)

    result = Admin::Auctions::Retire.new(actor: user, auction: auction).call

    refute result.success?
    assert_equal "Admin privileges required", result.error
    assert_equal :forbidden, result.code
    assert_equal "active", auction.reload.status
  end

  test "upsert returns invalid_state for invalid scheduling" do
    attrs = {
      title: "Bad Auction",
      description: "Desc",
      start_date: 2.days.from_now,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :pending
    }

    result = Admin::Auctions::Upsert.new(actor: @admin, attrs: attrs).call

    refute result.ok?
    assert_equal :invalid_state, result.code
    assert_match "end_time must be after start_date", result.error
  end
end
