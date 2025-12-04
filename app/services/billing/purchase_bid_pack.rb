module Billing
  class PurchaseBidPack
    Result = Struct.new(:success?, :message, :error, keyword_init: true)

    def initialize(user:, bid_pack:)
      @user = user
      @bid_pack = bid_pack
    end

    def call
      ActiveRecord::Base.transaction do
        @user.increment!(:bid_credits, @bid_pack.bids)
        Result.new(success?: true, message: "Bid pack purchased successfully!", error: nil)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, message: nil, error: "Validation error: #{e.message}")
    rescue => e
      Rails.logger.error("PurchaseBidPack Error: #{e.message}\n#{e.backtrace.join("\n")}")
      Result.new(success?: false, message: nil, error: "An unexpected error occurred: #{e.message}")
    end
  end
end
