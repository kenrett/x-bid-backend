class PlaceBid
  Result = Struct.new(:success?, :bid, :error, keyword_init: true)
  BID_INCREMENT = 0.01.to_d
  EXTENSION_WINDOW = 10.seconds
  MAX_RETRIES = 3

  attr_reader :auction

  def initialize(user:, auction:)
    @user = user
    @auction = auction
    @bid = nil
  end

  def call(broadcast: true)
    # Pre-transaction checks for immediate failure
    return Result.new(success?: false, error: "Auction is not active") unless @auction.active?
    return Result.new(success?: false, error: "Insufficient bid credits") if @user.bid_credits <= 0

    begin
      ActiveRecord::Base.transaction do
        # Calculate the intended new price based on the auction's state *before* the lock.
        new_price = @auction.current_price + BID_INCREMENT

        # Lock the auction row to prevent race conditions.
        @auction.lock!

        # After acquiring the lock, re-verify that our bid is still valid against the reloaded auction state.
        return Result.new(success?: false, error: "Another bid was placed first.") if @auction.current_price >= new_price

        @user.decrement!(:bid_credits)
        # Create the bid. The model validation will ensure its amount is > current_price.
        # If another bid was processed while this one was waiting for the lock, this will fail.
        @bid = @auction.bids.create!(user: @user, amount: new_price)
        Rails.logger.info "✅ Bid saved successfully: #{@bid.inspect}"
        # After the bid is successfully created, update the auction's price and winner.
        @auction.update!(current_price: new_price, winning_user: @user)
        extend_auction_if_needed!
      end
      broadcast_bid if broadcast
      Result.new(success?: true, bid: @bid)
    rescue ActiveRecord::RecordInvalid => e
      log_error(e)
      return Result.new(success?: false, error: "Another bid was placed first.") if e.record.errors.include?(:amount)
      Result.new(success?: false, error: "Bid could not be placed: #{e.message}")
    rescue => e
      log_error(e)
      Result.new(success?: false, error: "An unexpected error occurred.")
    end
  end

  private

  def extend_auction_if_needed!
    return unless @auction.ends_within?(EXTENSION_WINDOW)

    new_end_time = Time.current + EXTENSION_WINDOW
    @auction.update!(end_time: new_end_time)

    Rails.logger.info(
      "Auction ##{@auction.id} end time reset to #{EXTENSION_WINDOW} from now due to last-second bid ##{@bid.id} by user ##{@user.id}"
    )
  end

  def broadcast_bid
    return unless @bid.present?

    # Broadcast the update to the auction's stream. The `stop_stream` action,
    # called by the bidder's client, prevents this from being echoed to them.
    Rails.logger.info "📡 Broadcasting bid to Auction ##{@auction.id}"
    AuctionChannel.broadcast_to(
      @auction,
      {
        current_price: @auction.current_price,
        winning_user_name: @auction.winning_user&.name,
        end_time: @auction.end_time,
        bid: BidSerializer.new(@bid).as_json
      }
    )
  end

  def log_error(exception)
    Rails.logger.error(
      "PlaceBid Error | User: #{@user.id}, Auction: #{@auction.id}\n" \
      "Error: #{exception.message}\n#{exception.backtrace.join("\n")}"
    )
  end
end
