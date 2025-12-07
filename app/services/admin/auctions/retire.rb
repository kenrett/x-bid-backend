module Admin
  module Auctions
    class Retire
      def initialize(actor:, auction:, request: nil)
        @actor = actor
        @auction = auction
        @request = request
      end

      def call
        return unauthorized unless admin_actor?
        return ServiceResult.fail("Auction already inactive") if @auction.inactive?
        return ServiceResult.fail("Cannot retire an auction that has bids.") if @auction.bids.exists?

        if @auction.update(status: :inactive)
          AuditLogger.log(action: "auction.delete", actor: @actor, target: @auction, payload: { status: "inactive" }, request: @request)
          ServiceResult.ok
        else
          ServiceResult.fail(@auction.errors.full_messages.to_sentence)
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
