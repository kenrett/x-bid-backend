class AuctionChannel < ApplicationCable::Channel
  def subscribed
    @auction = Auction.find(params[:auction_id])
    stream_for @auction
  end

  def unsubscribed
    # Any cleanup if needed when channel is unsubscribed
  end
end
