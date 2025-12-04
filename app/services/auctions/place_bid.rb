module Auctions
  class PlaceBid
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
      return ServiceResult.fail("Auction is not active") unless @auction.active?
      return ServiceResult.fail("Insufficient bid credits") if @user.bid_credits <= 0

      begin
        ActiveRecord::Base.transaction do
          new_price = @auction.current_price + BID_INCREMENT
          @auction.lock!

          return ServiceResult.fail("Another bid was placed first.") if @auction.current_price >= new_price

          Credits::Debit.for_bid!(user: @user, auction: @auction)
          @bid = @auction.bids.create!(user: @user, amount: new_price)
          Rails.logger.info "✅ Bid saved successfully: #{@bid.inspect}"
          @auction.update!(current_price: new_price, winning_user: @user)
          Auctions::ExtendAuction.new(auction: @auction, window: EXTENSION_WINDOW).call
        end
        Auctions::Events.bid_placed(auction: @auction, bid: @bid) if broadcast
        ServiceResult.ok(bid: @bid)
      rescue ActiveRecord::RecordInvalid => e
        log_error(e)
        return ServiceResult.fail("Another bid was placed first.") if e.record.errors.include?(:amount)
        ServiceResult.fail("Bid could not be placed: #{e.message}")
      rescue => e
        log_error(e)
        ServiceResult.fail("An unexpected error occurred.")
      end
    end

    private

    def broadcast_bid
      # kept for backward compatibility if called directly
      return unless @bid.present?
      Auctions::Events.bid_placed(auction: @auction, bid: @bid)
    end

    def log_error(exception)
      Rails.logger.error(
        "PlaceBid Error | User: #{@user.id}, Auction: #{@auction.id}\n" \
        "Error: #{exception.message}\n#{exception.backtrace.join("\n")}"
      )
    end
  end
end
