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
      result = Auctions::AdminUpsert.new(actor: @admin, attrs: attrs).call
    assert_nil result.error
    assert result.record.persisted?
    assert_equal "New Auction", result.record.title
    end
  end

  test "admin upsert updates an auction" do
    auction = Auction.create!(title: "Old", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :pending)
    attrs = { status: :active }

    result = Auctions::AdminUpsert.new(actor: @admin, auction: auction, attrs: attrs).call

    assert_nil result.error
    assert_equal "active", auction.reload.status
  end

  test "retire fails when bids exist" do
    auction = Auction.create!(title: "Bidded", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    bidder = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    Bid.create!(user: bidder, auction: auction, amount: 2.0)

    result = Auctions::Retire.new(actor: @admin, auction: auction).call

    assert_equal "Cannot retire an auction that has bids.", result.error
  end

  test "retire sets auction inactive and logs audit" do
    auction = Auction.create!(title: "Retire Me", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)

    assert_difference -> { AuditLog.count }, +1 do
      result = Auctions::Retire.new(actor: @admin, auction: auction).call
    assert_nil result.error
    end

    assert_equal "inactive", auction.reload.status
  end
end
