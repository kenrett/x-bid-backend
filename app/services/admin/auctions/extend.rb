module Admin
  module Auctions
    class Extend
      def initialize(actor:, auction:, window: 10.seconds, request: nil)
        @actor = actor
        @auction = auction
        @window = window
        @request = request
      end

      def call(reference_time: Time.current)
        return unauthorized unless admin_actor?

        @auction.extend_end_time!(by: @window, reference_time: reference_time)
        AuditLogger.log(action: "auction.extend", actor: @actor, target: @auction, payload: { end_time: @auction.end_time }, request: @request)
        ServiceResult.ok(record: @auction, code: :ok)
      rescue ::Auction::InvalidState => e
        ServiceResult.fail(e.message, code: :invalid_state, record: @auction)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(@auction.errors.full_messages.to_sentence, code: :invalid_auction, record: @auction)
      end

      private

      def admin_actor?
        @actor&.admin? || @actor&.superadmin?
      end

      def unauthorized
        ServiceResult.fail("Admin privileges required", code: :forbidden)
      end
    end
  end
end
