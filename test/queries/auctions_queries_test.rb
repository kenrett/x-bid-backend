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
    @ended_auction = Auction.create!(
      title: "Ended Auction",
      description: "Desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: 1.0,
      status: :ended
    )
    @inactive_auction = Auction.create!(
      title: "Inactive Auction",
      description: "Desc",
      start_date: 4.days.ago,
      end_time: 3.days.ago,
      current_price: 1.0,
      status: :inactive
    )
    @bid = Bid.create!(user: @user, auction: @auction, amount: 6.0)
  end

  test "public index returns only active auctions and preloads winning users" do
    result = Auctions::Queries::PublicIndex.call

    auctions = result.records.to_a
    assert_equal [ @auction.id ], auctions.map(&:id)
    refute_includes auctions.map(&:id), @secondary_auction.id
    refute_includes auctions.map(&:id), @ended_auction.id
    refute_includes auctions.map(&:id), @inactive_auction.id
    assert auctions.first.association(:winning_user).loaded?
  end

  test "public show fetches auction with bids and winning user" do
    result = Auctions::Queries::PublicShow.call(params: { id: @auction.id })

    record = result.record
    assert_equal @auction.id, record.id
    assert_equal @bid.id, record.bids.first.id
    assert record.association(:bids).loaded?
    assert record.association(:winning_user).loaded?
  end

  test "public show returns not found result when missing" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Auctions::Queries::PublicShow.call(params: { id: -1 })
    end
  end
end
