module Auctions
  class PlaceBid
    BID_INCREMENT = 0.01.to_d
    EXTENSION_WINDOW = 10.seconds
    MAX_RETRIES = 3

    class AuctionNotActiveError < StandardError; end
    class InsufficientCreditsError < StandardError; end
    class BidRaceLostError < StandardError; end

    attr_reader :auction

    def initialize(user:, auction:)
      @user = user
      @auction = auction
      @bid = nil
    end

    def call(broadcast: true)
      validate_auction!
      ensure_user_has_credits!
      capture_bid_amount!

      with_lock_and_retries do
        persist_bid!
        extend_auction_if_needed!
      end

      publish_bid_placed_event if broadcast
      broadcast_list_update if broadcast
      ServiceResult.ok(code: :ok, message: "Bid placed", data: { bid: @bid, auction: @auction })
    rescue AuctionNotActiveError
      ServiceResult.fail("Auction is not active", code: :auction_not_active)
    rescue InsufficientCreditsError
      ServiceResult.fail("Insufficient bid credits", code: :insufficient_credits)
    rescue BidRaceLostError
      ServiceResult.fail("Another bid was placed first.", code: :bid_race_lost)
    rescue ActiveRecord::RecordInvalid => e
      handle_record_invalid(e)
    rescue => e
      log_error(e)
      ServiceResult.fail("An unexpected error occurred.", code: :unexpected_error)
    end

    private

    def validate_auction!
      raise AuctionNotActiveError unless @auction.active?
    end

    def ensure_user_has_credits!
      raise InsufficientCreditsError if @user.bid_credits <= 0
    end

    def capture_bid_amount!
      @bid_amount = @auction.current_price + BID_INCREMENT
    end

    def bid_amount
      @bid_amount
    end

    def with_lock_and_retries(&block)
      attempts = 0

      begin
        LockOrder.with_user_then_auction(user: @user, auction: @auction) { block.call }
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
        attempts += 1
        log_retry(e, attempts)
        retry if attempts < MAX_RETRIES

        log_error(e)
        raise
      end
    end

    def persist_bid!
      raise BidRaceLostError if @auction.current_price >= bid_amount

      debit_user_credits!
      @bid = @auction.bids.create!(user: @user, amount: bid_amount)
      AppLogger.log(event: "bid.saved", auction_id: @auction.id, bid_id: @bid.id, user_id: @user.id, amount: bid_amount)
      @auction.update!(current_price: bid_amount, winning_user: @user)
    end

    def debit_user_credits!
      Credits::Debit.for_bid!(user: @user, auction: @auction, locked: true)
    end

    def extend_auction_if_needed!
      Auctions::ExtendAuction.new(auction: @auction, window: EXTENSION_WINDOW).call
    end

    def publish_bid_placed_event
      Auctions::Events::BidPlaced.call(auction: @auction, bid: @bid) if @bid.present?
    end

    def handle_record_invalid(exception)
      log_error(exception)
      return ServiceResult.fail("Another bid was placed first.", code: :bid_race_lost) if exception.record.errors.include?(:amount)

      ServiceResult.fail("Bid could not be placed: #{exception.message}", code: :bid_invalid)
    end

    def broadcast_bid
      # kept for backward compatibility if called directly
      return unless @bid.present?
      Auctions::Events::BidPlaced.call(auction: @auction, bid: @bid)
    end

    def broadcast_list_update
      Auctions::Events::ListBroadcast.call(auction: @auction) if @auction.present?
    end

    def log_retry(error, attempt)
      AppLogger.log(
        event: "bid.retry",
        level: :warn,
        user_id: @user.id,
        auction_id: @auction.id,
        attempt: attempt,
        error_class: error.class.name,
        error_message: error.message
      )
    end

    def log_error(exception)
      AppLogger.error(
        event: "bid.error",
        error: exception,
        user_id: @user.id,
        auction_id: @auction.id
      )
    end
  end
end
