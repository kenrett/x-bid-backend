require "test_helper"

class AuctionsListBroadcastTest < ActiveSupport::TestCase
  def setup
    @auction = Auction.create!(
      title: "Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :pending
    )
    @user = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 1)
    bid = @auction.bids.create!(user: @user, amount: 2.0)
    @auction.update!(winning_user: @user, current_price: bid.amount)
  end

  test "broadcasts mapped payload to list stream" do
    broadcast_args = nil
    ActionCable.server.stub(:broadcast, ->(*args) { broadcast_args = args }) do
      Auctions::Events::ListBroadcast.call(auction: @auction)
    end

    assert_equal AuctionChannel.list_stream_for(@auction.storefront_key), broadcast_args.first
    payload = broadcast_args.last
    assert_equal @auction.id, payload[:id]
    assert_equal @auction.title, payload[:title]
    assert_equal "scheduled", payload[:status], "status should be mapped to external name"
    assert_in_delta 2.0, payload[:current_price], 0.001
    assert_equal @user.id, payload[:highest_bidder_id]
    assert_equal @user.name, payload[:winning_user_name]
    assert_equal @auction.bids.count, payload[:bid_count]
    assert_equal @auction.start_date, payload[:start_date]
    assert_equal @auction.end_time, payload[:end_time]
    assert_nil payload[:image_url]
    assert_equal @auction.description, payload[:description]
  end
end
