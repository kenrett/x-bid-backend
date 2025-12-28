class AuctionWinEmailJob < ApplicationJob
  queue_as :default

  def perform(settlement_id)
    TransactionalMailer.auction_win(settlement_id).deliver_now
  end
end
