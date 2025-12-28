module Fulfillment
  class ClaimAuction
    REQUIRED_ADDRESS_FIELDS = %w[name line1 city state postal_code country].freeze

    def self.call(user:, auction_id:, shipping_address:)
      new(user:, auction_id:, shipping_address:).call
    end

    def initialize(user:, auction_id:, shipping_address:)
      @user = user
      @auction_id = auction_id
      @shipping_address = shipping_address
    end

    def call
      return ServiceResult.fail("User must be provided", code: :invalid_user) unless user

      settlement = AuctionSettlement
        .includes(:auction, :winning_bid, :auction_fulfillment)
        .find_by(auction_id: auction_id, winning_user_id: user.id)
      return ServiceResult.fail("Win not found", code: :not_found) unless settlement

      address = normalize_address(shipping_address)
      missing = REQUIRED_ADDRESS_FIELDS.select { |key| address[key].blank? }
      if missing.any?
        return ServiceResult.fail(
          "Invalid shipping address",
          code: :invalid_address,
          details: { missing: missing }
        )
      end

      fulfillment = settlement.auction_fulfillment || AuctionFulfillment.new(auction_settlement: settlement, user: user)
      return ServiceResult.fail("Only the winning user may claim this win", code: :forbidden) if fulfillment.user_id != user.id
      return ServiceResult.fail("Win has already been claimed", code: :invalid_state) unless fulfillment.pending?

      AuctionFulfillment.transaction do
        fulfillment.save! if fulfillment.new_record?
        fulfillment.shipping_address = address
        fulfillment.transition_to!(:claimed)
      end

      ServiceResult.ok(code: :claimed, data: { settlement: settlement, fulfillment: fulfillment })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail("Claim failed: #{e.record.errors.full_messages.join(', ')}", code: :unprocessable_content)
    end

    private

    attr_reader :user, :auction_id, :shipping_address

    def normalize_address(address)
      raw = (address || {}).to_h
      raw.transform_values { |value| value.is_a?(String) ? value.strip : value }
    end
  end
end
