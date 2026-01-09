class AuctionWinEmailJob < ApplicationJob
  queue_as :default

  def perform(settlement_id, storefront_key: nil)
    with_storefront_context(storefront_key: storefront_key) do
      TransactionalMailer.auction_win(settlement_id).deliver_now
    end
  end
end
