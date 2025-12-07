module Admin
  module BidPacks
    class Retire < Admin::BaseCommand
      def initialize(actor:, bid_pack:, request: nil)
        super
      end

      private

      def perform
        return ServiceResult.fail("Bid pack already retired", code: :invalid_state) if @bid_pack.retired?

        if @bid_pack.update(status: :retired, active: false)
          AuditLogger.log(action: "bid_pack.delete", actor: @actor, target: @bid_pack, payload: { status: "retired" }, request: @request)
          ServiceResult.ok(record: @bid_pack)
        else
          ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence, code: :invalid_bid_pack, record: @bid_pack)
        end
      end
    end
  end
end
