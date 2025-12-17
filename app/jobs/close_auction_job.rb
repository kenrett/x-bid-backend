class CloseAuctionJob < ApplicationJob
  queue_as :default

  def perform(auction_id = nil)
    if auction_id
      auction = Auction.find_by(id: auction_id)
      Auctions::Close.call(auction: auction) if auction
      return
    end

    Auction.where(status: :active).where("end_time <= ?", Time.current).find_each do |auction|
      Auctions::Close.call(auction: auction)
    end
  end
end
