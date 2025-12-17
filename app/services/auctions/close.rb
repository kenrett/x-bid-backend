module Auctions
  class Close
    def self.call(auction:, reference_time: Time.current)
      new(auction: auction, reference_time: reference_time).call
    end

    def initialize(auction:, reference_time:)
      @auction = auction
      @reference_time = reference_time
    end

    def call
      return ServiceResult.ok(code: :already_closed, data: { auction: auction }) if auction.ended? || auction.cancelled? || auction.inactive?
      return ServiceResult.fail("Auction must be active to close", code: :invalid_state) unless auction.active?
      return ServiceResult.fail("Auction has not ended yet", code: :invalid_state) unless closeable?

      auction.close!
      Auctions::Events::ListBroadcast.call(auction: auction)
      ServiceResult.ok(code: :closed, data: { auction: auction, settlement: auction.settlement })
    rescue Auction::InvalidState => e
      ServiceResult.fail(e.message, code: :invalid_state)
    end

    private

    attr_reader :auction, :reference_time

    def closeable?
      auction.end_time.present? && auction.end_time <= reference_time
    end
  end
end
