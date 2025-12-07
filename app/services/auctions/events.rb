module Auctions
  module Events
    module_function

    def bid_placed(auction:, bid:)
      BidPlaced.call(auction: auction, bid: bid)
    end
  end
end
