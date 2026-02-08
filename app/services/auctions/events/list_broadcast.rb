module Auctions
  module Events
    class ListBroadcast
      def self.call(auction:)
        new(auction: auction).call
      end

      def initialize(auction:)
        @auction = auction
      end

      def call
        return unless auction

        ActionCable.server.broadcast(stream_name, payload)
        log_event
      rescue StandardError => e
        Rails.logger.error("Auctions::Events::ListBroadcast failed: #{e.message}")
      end

      private

      attr_reader :auction

      def stream_name
        AuctionChannel.list_stream_for(auction.storefront_key)
      end

      def payload
        {
          id: auction.id,
          title: auction.title,
          status: status_for_list,
          current_price: auction.current_price.to_f,
          highest_bidder_id: auction.winning_user_id,
          winning_user_name: auction.winning_user&.name,
          highest_bidder_name: auction.winning_user&.name,
          bid_count: bid_count,
          start_date: auction.start_date,
          end_time: auction.end_time,
          image_url: auction.image_url,
          description: auction.description
        }
      end

      def status_for_list
        Auctions::Status.to_api(auction.status)
      end

      def bid_count
        auction.bids.count
      end

      def log_event
        AppLogger.log(
          event: "auction.list_broadcast",
          auction_id: auction.id,
          status: status_for_list,
          bid_count: bid_count,
          current_price: auction.current_price
        )
      end
    end
  end
end
