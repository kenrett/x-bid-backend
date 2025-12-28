module Admin
  module Fulfillments
    class Complete < Admin::BaseCommand
      def initialize(actor:, fulfillment:, request: nil)
        super(actor: actor, fulfillment: fulfillment, request: request)
      end

      private

      def perform
        return ServiceResult.fail("Fulfillment not provided", code: :invalid_fulfillment) unless @fulfillment
        return ServiceResult.fail("Fulfillment must be shipped to complete", code: :invalid_state) unless @fulfillment.shipped?

        @fulfillment.with_lock do
          return ServiceResult.fail("Fulfillment must be shipped to complete", code: :invalid_state) unless @fulfillment.shipped?

          @fulfillment.transition_to!(:complete)

          AuditLogger.log(
            action: "fulfillment.complete",
            actor: @actor,
            target: @fulfillment,
            payload: {
              from: "shipped",
              to: "complete",
              auction_settlement_id: @fulfillment.auction_settlement_id
            },
            request: @request
          )

          AppLogger.log(
            event: "admin.fulfillments.complete",
            admin_id: @actor&.id,
            fulfillment_id: @fulfillment.id,
            auction_settlement_id: @fulfillment.auction_settlement_id
          )

          ServiceResult.ok(code: :complete, record: @fulfillment)
        end
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :unprocessable_content, record: @fulfillment)
      end
    end
  end
end
