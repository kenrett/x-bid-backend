module Admin
  module Auctions
    class Retire
      def initialize(actor:, auction:, request: nil)
        @actor = actor
        @auction = auction
        @request = request
      end

      def call
        return ServiceResult.fail("Auction already inactive") if @auction.inactive?
        return ServiceResult.fail("Cannot retire an auction that has bids.") if @auction.bids.exists?

        if @auction.update(status: :inactive)
          AuditLogger.log(action: "auction.delete", actor: @actor, target: @auction, payload: { status: "inactive" }, request: @request)
          ServiceResult.ok
        else
          ServiceResult.fail(@auction.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
