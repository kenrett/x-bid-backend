require "test_helper"

class BidPackTest < ActiveSupport::TestCase
  test "#as_json should include formatted pricePerBid for even division" do
    bid_pack = BidPack.new(name: "Test Pack", price: 150.00, bids: 300)
    json_output = bid_pack.as_json

    assert_equal "$0.50", json_output["pricePerBid"]
  end

  test "#as_json should include formatted pricePerBid with tilde for uneven division" do
    bid_pack = BidPack.new(name: "Test Pack", price: 42.00, bids: 69)
    json_output = bid_pack.as_json

    assert_match /~\$0.61/, json_output["pricePerBid"]
  end

  test "#as_json should handle zero bids gracefully" do
    bid_pack = BidPack.new(name: "Test Pack", price: 50.00, bids: 0)
    json_output = bid_pack.as_json

    assert_equal "$0.00", json_output["pricePerBid"]
  end
end
