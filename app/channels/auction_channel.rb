class AuctionChannel < ApplicationCable::Channel
  def subscribed
    if params[:stream] == "list"
      stream_from list_stream
      return
    end

    auction_id = params[:auction_id]

    # 1. First, check if the client even sent an ID
    unless auction_id
      Rails.logger.error "❌ SUBSCRIPTION REJECTED: No auction_id was provided by the client."
      reject
      return
    end

    # 2. Next, try to find the auction using the ID
    @auction = Auction.find_by(id: auction_id)

    # 3. Finally, subscribe if the auction was found, otherwise reject
    if @auction
      stream_for @auction
      Rails.logger.info "✅ Client successfully subscribed to stream for Auction ##{@auction.id}"
    else
      Rails.logger.error "❌ SUBSCRIPTION REJECTED: Could not find an Auction with ID #{auction_id}."
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

  # This action can be called by the client after a bid is placed to resume
  # receiving broadcasts for this auction.
  def start_stream
    stream_for @auction if @auction
  end

  private

  def list_stream
    "AuctionChannel:list"
  end
end
