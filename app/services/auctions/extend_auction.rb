module Auctions
  class ExtendAuction
    def initialize(auction:, window: 10.seconds)
      @auction = auction
      @window = window
    end

    def call(reference_time: Time.current)
      return false unless @auction.ends_within?(@window)

      new_end_time = reference_time + @window
      @auction.update!(end_time: new_end_time)
      AppLogger.log(event: "auction.extended", auction_id: @auction.id, window_seconds: @window, new_end_time: new_end_time)
      true
    end
  end
end
