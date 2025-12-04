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
      Rails.logger.info(
        "Auction ##{@auction.id} end time reset to #{@window.inspect} from now due to last-second bid on auction ##{@auction.id}"
      )
      true
    end
  end
end
