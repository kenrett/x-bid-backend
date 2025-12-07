module Admin
  module BidPacks
    class Upsert < Admin::BaseCommand
      def initialize(actor:, bid_pack: nil, attrs:, request: nil)
        bid_pack ||= ::BidPack.new
        super(actor: actor, bid_pack: bid_pack, attrs: attrs, request: request)
      end

      private

      def perform
        if @bid_pack.update(@attrs)
          AuditLogger.log(action: action_name, actor: @actor, target: @bid_pack, payload: @attrs, request: @request)
          ServiceResult.ok(record: @bid_pack)
        else
          ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence, code: :invalid_bid_pack, record: @bid_pack)
        end
      end

      def action_name
        @bid_pack.persisted? ? "bid_pack.update" : "bid_pack.create"
      end
    end
  end
end
