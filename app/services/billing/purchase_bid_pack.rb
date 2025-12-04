module Billing
  class PurchaseBidPack
    def initialize(user:, bid_pack:)
      @user = user
      @bid_pack = bid_pack
    end

    def call
      ActiveRecord::Base.transaction do
        Credits::Credit.for_refund!(user: @user, reason: "bid_pack_purchase", amount: @bid_pack.bids)
        ServiceResult.ok(message: "Bid pack purchased successfully!")
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail("Validation error: #{e.message}")
    rescue => e
      Rails.logger.error("PurchaseBidPack Error: #{e.message}\n#{e.backtrace.join("\n")}")
      ServiceResult.fail("An unexpected error occurred: #{e.message}")
    end
  end
end
