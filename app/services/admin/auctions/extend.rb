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
        return ServiceResult.fail("Auction not within extend window", code: :invalid_state) unless @auction.ends_within?(@window)

        new_end_time = reference_time + @window

        if @auction.update(end_time: new_end_time)
          AuditLogger.log(action: "auction.extend", actor: @actor, target: @auction, payload: { end_time: new_end_time }, request: @request)
          ServiceResult.ok(record: @auction, code: :ok)
        else
          ServiceResult.fail(@auction.errors.full_messages.to_sentence, code: :invalid_auction, record: @auction)
        end
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
