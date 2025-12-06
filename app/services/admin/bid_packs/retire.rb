module Admin
  module BidPacks
    class Retire
      def initialize(actor:, bid_pack:, request: nil)
        @actor = actor
        @bid_pack = bid_pack
        @request = request
      end

      def call
        return ServiceResult.fail("Bid pack already retired") if @bid_pack.retired?

        if @bid_pack.update(status: :retired, active: false)
          AuditLogger.log(action: "bid_pack.delete", actor: @actor, target: @bid_pack, payload: { status: "retired" }, request: @request)
          ServiceResult.ok(record: @bid_pack)
        else
          ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
