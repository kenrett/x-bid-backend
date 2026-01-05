module Api
  module V1
    class BidPacksController < ApplicationController
      before_action :authenticate_request!, only: [ :purchase ]

      # @summary List available bid packs
      # Publicly lists active bid packs available for purchase.
      # @response Bid packs (200) [Array<BidPack>]
      # @no_auth
      def index
        scope = BidPack.active

        ttl = 10.minutes
        expires_in ttl, public: true, must_revalidate: true, "s-maxage": ttl.to_i, stale_while_revalidate: 30.minutes

        last_modified = scope.maximum(:updated_at)&.utc || Time.at(0).utc
        etag = [ "bid-packs-index", last_modified.to_i, scope.count ]
        return unless stale?(etag: etag, last_modified: last_modified, public: true)

        bid_packs = scope
        render json: bid_packs
      end

      # @summary Purchase a bid pack for the current user
      # Creates a purchase for the given bid pack and credits the user after payment processing.
      # Requires `payment_intent_id` or `checkout_session_id` for idempotency.
      # @parameter id(path) [Integer] ID of the bid pack
      # @response Purchase started (200) [Hash{ message: String }]
      # @response Unauthorized (401) [Error]
      # @response Not found (404) [Error]
      # @response Validation error (422) [Error]
      def purchase
        bid_pack = BidPack.active.find(params[:id])
        result = Billing::PurchaseBidPack.new(
          user: @current_user,
          bid_pack: bid_pack,
          payment_intent_id: params[:payment_intent_id],
          checkout_session_id: params[:checkout_session_id]
        ).call

        if result.success?
          render json: { message: result.message }, status: :ok
        else
          render_error(code: :bid_pack_purchase_failed, message: result.error, status: :unprocessable_entity)
        end
      rescue ActiveRecord::RecordNotFound
        render_error(code: :not_found, message: "Bid pack not found", status: :not_found)
      end
    end
  end
end
