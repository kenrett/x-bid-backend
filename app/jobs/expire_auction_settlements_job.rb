class ExpireAuctionSettlementsJob < ApplicationJob
  queue_as :default

  def perform(reference_time = Time.current, storefront_key: nil)
    with_storefront_context(storefront_key: storefront_key) do
      cutoff = reference_time - AuctionSettlement::RETRY_WINDOW
      AuctionSettlement.where(status: [ :pending_payment, :payment_failed ])
        .where("ended_at <= ?", cutoff)
        .find_each do |settlement|
          settlement.cancel_for_non_payment!
          AppLogger.log(
            event: "auction.payment_expired",
            auction_id: settlement.auction_id,
            settlement_id: settlement.id,
            winning_user_id: settlement.winning_user_id
          )
        end
    end
  end
end
