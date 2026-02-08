module Api
  module V1
    class BidHistoryController < ApplicationController
      before_action :set_auction
      before_action :enforce_bid_history_detail_policy!

      # GET /api/v1/auctions/:auction_id/bid_history
      # @summary List bids for a given auction (newest first)
      # Returns the current bid list for an auction along with the winning user, if present.
      # @parameter auction_id(path) [Integer] ID of the auction
      # @response Bid history (200) [BidHistoryResponse]
      # @response Forbidden (403) [Error]
      # @response Not found (404) [Error]
      # @no_auth
      def index
        bids = @auction.bids.order(created_at: :desc).includes(:user)

        render json: {
          auction: {
            winning_user_id: @auction.winning_user_id,
            winning_user_name: @auction.winning_user&.name
          },
          bids: bids.map { |bid| BidSerializer.new(bid).as_json }
        }
      end

      private

      def set_auction
        @storefront_key = Current.storefront_key
        scoped = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: @storefront_key)
        @auction = scoped.find(params[:auction_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def enforce_bid_history_detail_policy!
        return if performed? || @auction.blank?

        enforce_marketplace_policy!
        enforce_adult_policy!
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def enforce_marketplace_policy!
        return if Storefront::Policy.can_view_marketplace_detail?(storefront_key: @storefront_key, auction: @auction)

        raise ActiveRecord::RecordNotFound
      end

      def enforce_adult_policy!
        return unless Storefront::Policy.adult_detail?(@auction)

        session_token = Auth::OptionalSession.session_token_from_request(request)
        return if Storefront::Policy.can_view_adult_detail?(storefront_key: @storefront_key, session_token: session_token, auction: @auction)

        expires_now
        response.headers["Cache-Control"] = "no-store"
        render_error(
          code: "AGE_GATE_REQUIRED",
          message: "Age gate acceptance required to view this item.",
          status: :forbidden
        )
      end

      def render_not_found
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end
    end
  end
end
