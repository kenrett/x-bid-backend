module Billing
  class PurchaseBidPack
    def initialize(user:, bid_pack:)
      @user = user
      @bid_pack = bid_pack
    end

    def call
      ActiveRecord::Base.transaction do
        Credits::Credit.for_refund!(user: @user, reason: "bid_pack_purchase", amount: @bid_pack.bids)
        AppLogger.log(event: "billing.purchase_bid_pack", user_id: @user.id, bid_pack_id: @bid_pack.id, bids: @bid_pack.bids)
        ServiceResult.ok(message: "Bid pack purchased successfully!")
      end
    rescue ActiveRecord::RecordInvalid => e
      AppLogger.error(event: "billing.purchase_bid_pack.error", error: e, user_id: @user.id, bid_pack_id: @bid_pack.id)
      ServiceResult.fail("Validation error: #{e.message}")
    rescue => e
      AppLogger.error(event: "billing.purchase_bid_pack.error", error: e, user_id: @user.id, bid_pack_id: @bid_pack.id)
      ServiceResult.fail("An unexpected error occurred: #{e.message}")
    end
  end
end
