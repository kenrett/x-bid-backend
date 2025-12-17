require "test_helper"

class AuctionTest < ActiveSupport::TestCase
  setup do
    @auction = Auction.new(
      title: "Vintage Watch",
      description: "A beautiful vintage watch.",
      start_date: Time.current,
      current_price: 100.00,
      status: :active
    )
  end

  test "should be valid with valid attributes" do
    assert @auction.valid?
  end

  test "should be invalid without a title" do
    @auction.title = nil
    refute @auction.valid?
    assert_not_nil @auction.errors[:title]
  end

  test "should not allow negative current_price" do
    @auction.current_price = -10
    refute @auction.valid?
    assert_not_nil @auction.errors[:current_price]
  end

  test "#closed? should be true if status is not active" do
    @auction.status = :ended
    assert @auction.closed?
  end

  test "#closed? should be true if end_time is in the past" do
    @auction.status = :active
    @auction.end_time = 1.hour.ago
    assert @auction.closed?
  end

  test "#closed? should be false if active and end_time is in the future" do
    @auction.status = :active
    @auction.end_time = 1.hour.from_now
    refute @auction.closed?
  end

  test "#ends_within? should be true if end_time is within the duration" do
    @auction.end_time = 5.seconds.from_now
    assert @auction.ends_within?(10.seconds)
  end

  test "#ends_within? should be false if end_time is outside the duration" do
    @auction.end_time = 15.seconds.from_now
    refute @auction.ends_within?(10.seconds)
  end

  test "update_details! restricts to permitted fields and validates times" do
    @auction.end_time = 1.hour.from_now
    @auction.save!

    assert_raises(ArgumentError) { @auction.update_details!({ foo: "bar" }) }

    assert_raises(Auction::InvalidState) do
      @auction.update_details!(start_date: 2.hours.from_now, end_time: 1.hour.from_now)
    end

    @auction.update_details!(title: "Updated", start_date: Time.current, end_time: 2.hours.from_now)
    assert_equal "Updated", @auction.reload.title
  end

  test "schedule! sets pending with validated times" do
    auction = Auction.create!(title: "Sched", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :pending)

    assert_raises(Auction::InvalidState) do
      auction.schedule!(starts_at: 1.day.from_now, ends_at: 1.hour.from_now)
    end

    auction.schedule!(starts_at: Time.current, ends_at: 1.day.from_now)
    assert_equal "pending", auction.reload.status
  end

  test "start! only allowed from pending" do
    auction = Auction.create!(title: "Startable", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :pending)
    auction.start!
    assert_equal "active", auction.reload.status

    assert_raises(Auction::InvalidState) { auction.start! }
  end

  test "extend_end_time! requires active and window" do
    auction = Auction.create!(title: "Extendable", description: "Desc", start_date: Time.current, end_time: 5.seconds.from_now, current_price: 1.0, status: :active)
    reference_time = Time.current

    auction.extend_end_time!(by: 10.seconds, reference_time: reference_time)
    assert_in_delta reference_time + 10.seconds, auction.reload.end_time, 1

    auction.update!(status: :ended)
    assert_raises(Auction::InvalidState) { auction.extend_end_time!(by: 10.seconds) }
  end

  test "close! only from active" do
    auction = Auction.create!(title: "Closable", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    auction.close!
    assert_equal "ended", auction.reload.status
    assert_equal "no_winner", auction.settlement.status

    assert_raises(Auction::InvalidState) { auction.close! }
  end

  test "close! captures winning bid and settlement snapshot" do
    user = User.create!(name: "Winner", email_address: "winner@example.com", password: "password", bid_credits: 0)
    auction = Auction.create!(title: "Prize", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 4.0, status: :active, winning_user: user)
    bid = Bid.create!(auction: auction, user: user, amount: 5.0)
    auction.update!(current_price: 5.0)

    auction.close!

    settlement = auction.settlement
    assert_equal "pending_payment", settlement.status
    assert_equal user.id, settlement.winning_user_id
    assert_equal bid.id, settlement.winning_bid_id
    assert_equal 5.0, settlement.final_price.to_f
    assert settlement.ended_at.present?
  end

  test "cancel! only from pending or active" do
    pending = Auction.create!(title: "Pending", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :pending)
    active = Auction.create!(title: "Active", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)

    pending.cancel!
    active.cancel!

    assert_equal "cancelled", pending.reload.status
    assert_equal "cancelled", active.reload.status

    assert_raises(Auction::InvalidState) { pending.cancel! }
  end

  test "retire! requires no bids and not already inactive" do
    auction = Auction.create!(title: "Retirable", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    auction.retire!
    assert_equal "inactive", auction.reload.status

    assert_raises(Auction::InvalidState) { auction.retire! }

    bidder = User.create!(name: "Bidder", email_address: "bidder_retire@example.com", password: "password", bid_credits: 1)
    bid_auction = Auction.create!(title: "Bidded", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    Bid.create!(auction: bid_auction, user: bidder, amount: 2.0)

    assert_raises(Auction::InvalidState) { bid_auction.retire! }
  end

  test "#as_json exposes mapped status and bidder info" do
    @auction.status = :pending
    @auction.winning_user = User.new(name: "Winner")
    json = @auction.as_json

    assert_equal "scheduled", json["status"]
    assert_nil json["highest_bidder_id"]
    assert_equal "Winner", json["winning_user_name"]
    # Money fields serialize as strings via JSON; ensure value matches.
    assert_equal @auction.current_price.to_s, json["current_price"]
  end

  test "bids are ordered newest first by default" do
    @auction.save!
    user = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    @auction.update!(current_price: 0.0)
    older = Bid.create!(auction: @auction, user: user, amount: 1.0, created_at: 10.minutes.ago)
    newer = Bid.create!(auction: @auction, user: user, amount: 2.0, created_at: 1.minute.ago)

    assert_equal [ newer.id, older.id ], @auction.bids.pluck(:id)
  end
end
