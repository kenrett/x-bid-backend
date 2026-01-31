require "time"

module Activity
  module Queries
    class FeedForUser
      # Activity feed contract (event-backed).
      #
      # Endpoint: GET /api/v1/me/activity (Api::V1::Me::ActivityController#index)
      #
      # Response shape:
      #   {
      #     items: [ActivityItem...],
      #     page: Integer,
      #     per_page: Integer,
      #     has_more: Boolean,
      #     next_cursor: String | nil
      #   }
      #
      # ActivityItem shape (Hash):
      #   {
      #     type: String,            # client mapping key
      #     created_at: Time,        # serialized to JSON datetime
      #     auction: {
      #       id: Integer,
      #       title: String,
      #       status: String,        # Auction#external_status
      #       ends_at: Time,
      #       current_price: Decimal
      #     } | nil,
      #     data: Hash               # type-specific payload
      #   }
      #
      # Activity `type` values are appended to ActivityEvent on write paths:
      # - "bid_placed"
      # - "auction_watched"
      # - "auction_won"
      # - "auction_lost"
      # - "purchase_completed"
      # - "fulfillment_status_changed"
      # - "watch_removed"
      #
      # Sorting: newest-first by (occurred_at, id).
      # Pagination: cursor-based using (occurred_at, id); page/per_page remains for legacy clients.
      #
      # NOTE: Notifications are a separate API (`/api/v1/me/notifications`) and use `kind` as their client mapping key.
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
        events = events_relation.limit(per_page + 1).to_a
        has_more = events.length > per_page
        page_records = events.first(per_page)

        @meta = {
          page: page_number,
          per_page: per_page,
          has_more: has_more,
          next_cursor: has_more ? cursor_for(page_records.last) : nil
        }

        @records = build_items(page_records)
        self
      end

      private

      attr_reader :user, :params

      def build_items(events)
        auction_ids = events.map { |event| event.data.is_a?(Hash) ? event.data["auction_id"] : nil }.compact.uniq
        auctions_by_id = auction_ids.empty? ? {} : Auction.where(id: auction_ids).index_by(&:id)

        events.map do |event|
          data = event.data.is_a?(Hash) ? event.data : {}
          auction = auctions_by_id[data["auction_id"]]

          {
            type: event.event_type,
            occurred_at: event.occurred_at,
            created_at: event.occurred_at,
            auction: serialize_auction(auction),
            data: data
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

      def cursor
        params[:cursor].to_s.presence
      end

      def events_relation
        relation = ActivityEvent.where(user_id: user.id)
        relation = apply_cursor(relation) if cursor.present?
        relation = relation.order(occurred_at: :desc, id: :desc)
        relation = relation.offset((page_number - 1) * per_page) if cursor.blank? && page_number > 1
        relation
      end

      def apply_cursor(relation)
        occurred_at, id = parse_cursor(cursor)
        relation.where("occurred_at < ? OR (occurred_at = ? AND id < ?)", occurred_at, occurred_at, id)
      end

      def parse_cursor(raw_cursor)
        parts = raw_cursor.to_s.split("|", 2)
        raise ArgumentError, "Invalid cursor" if parts.length != 2

        occurred_at = Time.iso8601(parts[0])
        id = Integer(parts[1])
        [ occurred_at, id ]
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid cursor"
      end

      def cursor_for(event)
        return nil unless event

        "#{event.occurred_at.utc.iso8601(6)}|#{event.id}"
      end
    end
  end
end
