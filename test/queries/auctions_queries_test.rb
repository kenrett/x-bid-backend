require "test_helper"

class AuctionsQueriesTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @winner = User.create!(name: "Winner", email_address: "winner@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Main Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 5.0,
      status: :active,
      winning_user: @winner
    )
    @secondary_auction = Auction.create!(
      title: "Secondary Auction",
      description: "Desc",
      start_date: 2.days.from_now,
      end_time: 3.days.from_now,
      current_price: 1.0,
      status: :pending
    )
    @bid = Bid.create!(user: @user, auction: @auction, amount: 6.0)
  end

  test "public index scopes projection and preloads winning users" do
    result = Auctions::Queries::PublicIndex.new.call

    assert result.success?
    auctions = result.records.to_a
    assert_equal [ @auction.id, @secondary_auction.id ].sort, auctions.map(&:id).sort
    assert auctions.first.association(:winning_user).loaded?
  end

  test "public show fetches auction with bids and winning user" do
    result = Auctions::Queries::PublicShow.new(id: @auction.id).call

    assert result.success?
    record = result.record
    assert_equal @auction.id, record.id
    assert_equal @bid.id, record.bids.first.id
    assert record.association(:bids).loaded?
    assert record.association(:winning_user).loaded?
  end

  test "public show returns not found result when missing" do
    result = Auctions::Queries::PublicShow.new(id: -1).call

    refute result.success?
    assert_equal "Auction not found", result.error
    assert_equal :not_found, result.code
  end
end
