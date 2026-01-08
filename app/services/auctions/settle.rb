module Auctions
  class Settle
    def self.call(auction:)
      new(auction: auction).call
    end

    def initialize(auction:)
      @auction = auction
    end

    def call
      return ServiceResult.fail("Auction must be ended to settle", code: :invalid_state) unless auction.ended?

      settlement = AuctionSettlement.find_by(auction: auction)
      return ServiceResult.ok(code: :already_settled, data: { settlement: settlement }) if settlement

      winning_bid = auction.winning_bid
      winning_user = auction.winning_user || winning_bid&.user
      final_price = auction.current_price || 0
      status = winning_user.present? ? :pending_payment : :no_winner

      settlement = AuctionSettlement.create!(
        auction: auction,
        winning_user: winning_user,
        winning_bid: winning_bid,
        final_price: final_price,
        currency: "usd",
        status: status,
        ended_at: Time.current,
        storefront_key: auction.storefront_key
      )

      if settlement.pending_payment?
        ExpireAuctionSettlementsJob.set(wait_until: settlement.retry_window_ends_at).perform_later
      end

      AppLogger.log(
        event: "auction.settled",
        auction_id: auction.id,
        settlement_id: settlement.id,
        winning_user_id: winning_user&.id,
        winning_bid_id: winning_bid&.id,
        final_price: final_price
      )
      AuditLogger.log(
        action: "auction.settled",
        user: winning_user,
        target: settlement,
        payload: {
          auction_id: auction.id,
          settlement_id: settlement.id,
          winning_user_id: winning_user&.id,
          winning_bid_id: winning_bid&.id,
          final_price: final_price
        }.compact
      )

      ServiceResult.ok(code: :settled, data: { settlement: settlement })
    rescue ActiveRecord::RecordNotUnique
      settlement = AuctionSettlement.find_by(auction: auction)
      ServiceResult.ok(code: :already_settled, data: { settlement: settlement })
    end

    private

    attr_reader :auction
  end
end
