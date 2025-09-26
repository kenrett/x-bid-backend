class PlaceBid
  Result = Struct.new(:success?, :error, :bid, keyword_init: true)
  BID_INCREMENT = 0.01.to_d

  def initialize(user:, auction:)
    @user = user
    @auction = auction
  end

  def call
    return failure("Auction is closed") if @auction.closed?
    return failure("Insufficient bid credits") if @user.bid_credits <= 0

    Bid.transaction do
      # Lock auction row so only one bid is processed at a time
      @auction.lock!

      new_price = @auction.current_price + BID_INCREMENT
      bid = @auction.bids.build(user: @user, amount: new_price)

      if bid.save
        # Deduct one credit from the user
        @user.decrement!(:bid_credits, 1)

        # Update auction price and current highest bidder
        @auction.update!(
          current_price: new_price,
          winning_user: @user,
          end_time: [@auction.end_time, 10.seconds.from_now].compact.max # extend timer
        )

        # Broadcast via Action Cable
        AuctionChannel.broadcast_to(@auction, {
          current_price: @auction.current_price,
          highest_bidder: @user.id,
          bid: { id: bid.id, amount: bid.amount, user_id: bid.user_id, created_at: bid.created_at }
        })

        return success(bid)
      else
        raise ActiveRecord::Rollback, "Bid failed"
      end
    end
  rescue => e
    failure(e.message)
  end

  private

  def success(bid)
    Result.new(success?: true, bid: bid)
  end

  def failure(message)
    Result.new(success?: false, error: message)
  end
end
