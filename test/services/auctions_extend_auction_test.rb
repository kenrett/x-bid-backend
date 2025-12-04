require "test_helper"

class AuctionsExtendAuctionTest < ActiveSupport::TestCase
  def setup
    @auction = Auction.create!(
      title: "Extendable",
      description: "Desc",
      start_date: 1.day.ago,
      end_time: 5.seconds.from_now,
      current_price: 1.0,
      status: :active
    )
  end

  test "extends auction within window" do
    service = Auctions::ExtendAuction.new(auction: @auction, window: 10.seconds)
    assert service.call(reference_time: Time.current)
    assert_in_delta Time.current + 10.seconds, @auction.reload.end_time, 1.second
  end

  test "does nothing when outside window" do
    @auction.update!(end_time: 30.seconds.from_now)
    service = Auctions::ExtendAuction.new(auction: @auction, window: 10.seconds)
    refute service.call(reference_time: Time.current)
  end
end
