module Api
  module V1
    class BidsController < ApplicationController
      before_action :authenticate_request!
      before_action :require_verified_email!

      # @summary Place a bid on an auction
      # Places a bid for the current user on the specified auction.
      # @parameter auction_id(path) [Integer] ID of the auction
      # @response Bid placed (200) [BidPlacementResponse]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Not found (404) [Error]
      # @response Validation error (422) [Error]
      def create
        storefront_key = Current.storefront_key
        auction = scoped_auction_for_bid(storefront_key: storefront_key)
        return unless enforce_bid_detail_policy!(auction: auction, storefront_key: storefront_key)

        result = Auctions::PlaceBid.new(user: @current_user, auction: auction).call

        if result.success?
          # After a successful bid, include the user's new credit balance in the response
          # so the frontend can update its state immediately.
          # We use a serializer for the bid to ensure consistent formatting.
          render json: {
            success: true, bid: BidSerializer.new(result.bid).as_json, bidCredits: @current_user.bid_credits
          }, status: :ok
        else
          render_error(code: error_code_for(result), message: error_message_for(result), status: :unprocessable_content)
        end
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Auction not found", status: :not_found)
      end

      private

      def scoped_auction_for_bid(storefront_key:)
        scoped = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: storefront_key)
        scoped.find(params[:auction_id])
      end

      def enforce_bid_detail_policy!(auction:, storefront_key:)
        return false unless enforce_marketplace_policy!(auction: auction, storefront_key: storefront_key)

        enforce_adult_policy!(auction: auction, storefront_key: storefront_key)
      end

      def enforce_marketplace_policy!(auction:, storefront_key:)
        return true if Storefront::Policy.can_view_marketplace_detail?(storefront_key: storefront_key, auction: auction)

        raise ActiveRecord::RecordNotFound
      end

      def enforce_adult_policy!(auction:, storefront_key:)
        return true unless Storefront::Policy.adult_detail?(auction)
        return true if Storefront::Policy.can_view_adult_detail?(storefront_key: storefront_key, session_token: @current_session_token, auction: auction)

        render_error(
          code: "AGE_GATE_REQUIRED",
          message: "Age gate acceptance required to view this item.",
          status: :forbidden
        )
        false
      end

      def error_message_for(result)
        case result.code
        when :auction_not_active then "Auction is not active"
        when :insufficient_credits then "Insufficient bid credits"
        when :bid_race_lost then "Another bid was placed first."
        when :bid_invalid then "Bid could not be placed."
        else
          result.error || "Bid could not be placed."
        end
      end

      def error_code_for(result)
        result.code || :bid_error
      end
    end
  end
end
