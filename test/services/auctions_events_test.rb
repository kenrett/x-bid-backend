require "test_helper"

class AuctionsEventsTest < ActiveSupport::TestCase
  def setup
    @auction = Auction.create!(title: "Auction", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @bid = Bid.create!(user: @user, auction: @auction, amount: 2.0)
    @auction.update!(winning_user: @user, current_price: @bid.amount)
  end

  test "broadcasts bid placed event with payload" do
    broadcast_args = nil
    logged = nil

    AuctionChannel.stub(:broadcast_to, ->(*args) { broadcast_args = args }) do
      AppLogger.stub(:log, ->(**context) { logged = context }) do
        Auctions::Events::BidPlaced.call(auction: @auction, bid: @bid)
      end
    end

    assert_equal @auction, broadcast_args.first
    payload = broadcast_args.last
    assert_equal @auction.id, payload[:auction_id]
    assert_equal @auction.current_price, payload[:current_price]
    assert_equal({ id: @user.id, name: @user.name }, payload[:winning_user])
    assert_equal @auction.end_time, payload[:end_time]
    assert_equal BidSerializer.new(@bid).as_json, payload[:bid]

    assert_equal "auction.bid_placed", logged[:event]
    assert_equal @auction.id, logged[:auction_id]
    assert_equal @bid.id, logged[:bid_id]
    assert_equal @user.id, logged[:user_id]
  end
end
