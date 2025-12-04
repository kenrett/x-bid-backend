module Auctions
  module Events
    module_function

    def bid_placed(auction:, bid:)
      return unless auction && bid

      AuctionChannel.broadcast_to(
        auction,
        {
          current_price: auction.current_price,
          winning_user_name: auction.winning_user&.name,
          end_time: auction.end_time,
          bid: BidSerializer.new(bid).as_json
        }
      )
    rescue StandardError => e
      Rails.logger.error("Auctions::Events.bid_placed failed: #{e.message}")
    end
  end
end
