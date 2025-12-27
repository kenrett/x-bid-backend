module Activity
  module Queries
    class FeedForUser
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      attr_reader :records, :meta

      def self.call(user:, params: {})
        new(user: user, params: params).call
      end

      def initialize(user:, params: {})
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @params = (params || {}).dup
        @records = []
        @meta = {}
      end

      def call
        items = []

        items.concat(bid_items)
        items.concat(watch_items)
        items.concat(outcome_items)

        items.sort_by! { |item| [ item.fetch(:created_at).to_i, item.fetch(:type), item.dig(:auction, :id).to_i ] }
        items.reverse!

        page_records = paginated(items)

        @meta = {
          page: page_number,
          per_page: per_page,
          has_more: page_records.length > per_page
        }

        @records = page_records.first(per_page)
        self
      end

      private

      attr_reader :user, :params

      def paginated(items)
        items
          .drop((page_number - 1) * per_page)
          .first(per_page + 1)
      end

      def bid_items
        Bids::Queries::ForUser.call(user: user).records.map do |bid|
          {
            type: "bid_placed",
            created_at: bid.created_at,
            auction: serialize_auction(bid.auction),
            data: {
              bid_id: bid.id,
              amount: bid.amount
            }
          }
        end
      end

      def watch_items
        Auctions::Queries::WatchedByUser.call(user: user).records.map do |watch|
          {
            type: "auction_watched",
            created_at: watch.created_at,
            auction: serialize_auction(watch.auction),
            data: {
              watch_id: watch.id
            }
          }
        end
      end

      def outcome_items
        Auctions::Queries::OutcomesForUser.call(user: user).records.map do |outcome|
          auction = outcome.auction
          {
            type: outcome.type,
            created_at: outcome.created_at,
            auction: serialize_auction(auction),
            data: {
              winning_user_id: auction.winning_user_id
            }
          }
        end
      end

      def serialize_auction(auction)
        return nil unless auction

        {
          id: auction.id,
          title: auction.title,
          status: auction.external_status,
          ends_at: auction.end_time,
          current_price: auction.current_price
        }
      end

      def page_number
        value = params[:page].to_i
        value.positive? ? value : 1
      end

      def per_page
        value = params[:per_page].to_i
        return DEFAULT_PER_PAGE if value <= 0

        [ value, MAX_PER_PAGE ].min
      end
    end
  end
end
