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
end
