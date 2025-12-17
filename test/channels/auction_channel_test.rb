require "test_helper"

class AuctionChannelTest < ActionCable::Channel::TestCase
  def setup
    @auction = Auction.create!(
      title: "Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )
  end

  test "streams list feed when stream param is list" do
    subscribe(stream: "list")
    assert subscription.confirmed?
    assert stream_exists_for?(list_stream_name)
  end

  test "rejects subscription when auction_id is missing" do
    subscribe
    assert subscription.rejected?
  end

  test "rejects subscription when auction does not exist" do
    subscribe(auction_id: 999_999)
    assert subscription.rejected?
  end

  test "streams for valid auction" do
    subscribe(auction_id: @auction.id)
    assert subscription.confirmed?
    assert_has_stream_for @auction
  end

  test "stop_stream stops stream" do
    subscribe(auction_id: @auction.id)
    perform :stop_stream
    refute stream_exists_for?(@auction)
  end

  test "start_stream resumes stream" do
    subscribe(auction_id: @auction.id)
    perform :stop_stream
    refute stream_exists_for?(@auction)
    perform :start_stream
    assert stream_exists_for?(@auction)
  end

  private

  def stream_exists_for?(target)
    streams = subscription.send(:streams)
    expected = target.is_a?(Auction) ? subscription.send(:broadcasting_for, target) : target
    streams&.include?(expected)
  end

  def list_stream_name
    "AuctionChannel:list"
  end
end
