module Auctions
  module Events
    class BidPlaced
      def self.call(auction:, bid:)
        new(auction: auction, bid: bid).call
      end

      def initialize(auction:, bid:)
        @auction = auction
        @bid = bid
      end

      def call
        return unless auction && bid

        broadcast(payload)
        log_event
      rescue StandardError => e
        Rails.logger.error("Auctions::Events::BidPlaced failed: #{e.message}")
      end

      private

      attr_reader :auction, :bid

      # Payload contract:
      # {
      #   auction_id: Integer,
      #   current_price: Decimal,
      #   winning_user: { id: Integer, name: String } | nil,
      #   end_time: Time,
      #   bid: Hash (BidSerializer)
      # }
      def payload
        {
          auction_id: auction.id,
          current_price: auction.current_price,
          winning_user: winning_user_payload,
          end_time: auction.end_time,
          bid: BidSerializer.new(bid).as_json
        }
      end

      def winning_user_payload
        return unless auction.winning_user

        {
          id: auction.winning_user.id,
          name: auction.winning_user.name
        }
      end

      def broadcast(body)
        AuctionChannel.broadcast_to(auction, body)
      end

      def log_event
        AppLogger.log(
          event: "auction.bid_placed",
          auction_id: auction.id,
          bid_id: bid.id,
          user_id: bid.user_id,
          current_price: auction.current_price
        )
      end
    end
  end
end
