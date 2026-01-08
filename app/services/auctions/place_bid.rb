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
      @starting_price = auction.current_price
      @bid_amount = @starting_price + BID_INCREMENT
    end

    def call(broadcast: true)
      validate_auction!
      ensure_user_has_credits!

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
      raise InsufficientCreditsError if Credits::Balance.for_user(@user) <= 0
    end

    def bid_amount
      @bid_amount
    end

    def with_lock_and_retries(&block)
      attempts = 0

      begin
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        LockOrder.with_user_then_auction(user: @user, auction: @auction) { block.call }
      rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
        attempts += 1
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        log_retry(e, attempts, elapsed_ms: elapsed_ms)
        retry if attempts < MAX_RETRIES

        log_error(e)
        raise
      end
    end

    def persist_bid!
      @auction.reload(lock: true)
      current = @auction.current_price
      raise BidRaceLostError if current != @starting_price
      raise BidRaceLostError if current >= bid_amount

      resolved_storefront_key = storefront_key_for_write

      debit_user_credits!
      @bid = @auction.bids.create!(user: @user, amount: bid_amount, storefront_key: resolved_storefront_key)

      @auction.update!(current_price: bid_amount, winning_user: @user)
      record_bid_spent_money_event!(storefront_key: resolved_storefront_key)
      AppLogger.log(event: "bid.saved", auction_id: @auction.id, bid_id: @bid.id, user_id: @user.id, amount: bid_amount)
      AuditLogger.log(
        action: "auction.bid.placed",
        actor: @user,
        user: @user,
        payload: {
          auction_id: @auction.id,
          bid_id: @bid.id,
          amount: bid_amount
        }
      )
    end

    def debit_user_credits!
      Credits::Debit.for_bid!(
        user: @user,
        auction: @auction,
        idempotency_key: "bid_debit:user:#{@user.id}:auction:#{@auction.id}:amount:#{bid_amount}",
        locked: true,
        storefront_key: storefront_key_for_write
      )
    end

    def record_bid_spent_money_event!(storefront_key:)
      MoneyEvents::Record.call(
        user: @user,
        event_type: :bid_spent,
        amount_cents: -1,
        currency: "usd",
        source: @bid,
        occurred_at: Time.current,
        storefront_key: storefront_key
      )
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

    def log_retry(error, attempt, elapsed_ms:)
      AppLogger.log(
        event: "bid.retry",
        level: :warn,
        user_id: @user.id,
        auction_id: @auction.id,
        attempt: attempt,
        lock_wait_ms: elapsed_ms,
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

    def storefront_key_for_write
      Current.storefront_key.to_s.presence || @auction.storefront_key.to_s.presence
    end
  end
end
