module Admin
  module Auctions
    class Retire < Admin::BaseCommand
      def initialize(actor:, auction:, request: nil)
        super
      end

      private

      def perform
        @auction.retire!
        AuditLogger.log(action: "auction.delete", actor: @actor, target: @auction, payload: { status: "inactive" }, request: @request)
        ServiceResult.ok
      rescue ::Auction::InvalidState => e
        ServiceResult.fail(e.message, code: :invalid_state, record: @auction)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(@auction.errors.full_messages.to_sentence, code: :invalid_auction, record: @auction)
      end
    end
  end
end
