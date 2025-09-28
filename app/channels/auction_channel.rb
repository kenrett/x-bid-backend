class AuctionChannel < ApplicationCable::Channel
  # Called when a consumer successfully becomes a subscriber to this channel.
  def subscribed
    @auction = Auction.find_by(id: params[:id])
    if @auction
      stream_for @auction
    else
      reject
    end
  end

  # Called when a consumer unsubscribes from the channel.
  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
  # This action is called by the client just before making a bid via HTTP.
  # It temporarily stops this connection from receiving broadcasts for this auction,
  # preventing the user from receiving an echo of their own bid.
  def stop_stream
    stop_stream_for @auction if @auction
  end
end