module Admin
  module BidPacks
    class Upsert
      def initialize(actor:, bid_pack: nil, attrs:, request: nil)
        @actor = actor
        @bid_pack = bid_pack || ::BidPack.new
        @attrs = attrs
        @request = request
      end

      def call
        if @bid_pack.update(@attrs)
          AuditLogger.log(action: action_name, actor: @actor, target: @bid_pack, payload: @attrs, request: @request)
          ServiceResult.ok(record: @bid_pack)
        else
          ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence)
        end
      end

      private

      def action_name
        @bid_pack.persisted? ? "bid_pack.update" : "bid_pack.create"
      end
    end
  end
end
