module Admin
  module Fulfillments
    class Ship < Admin::BaseCommand
      def initialize(actor:, fulfillment:, shipping_carrier:, tracking_number:, request: nil)
        super(
          actor: actor,
          fulfillment: fulfillment,
          shipping_carrier: shipping_carrier,
          tracking_number: tracking_number,
          request: request
        )
      end

      private

      def perform
        return ServiceResult.fail("Fulfillment not provided", code: :invalid_fulfillment) unless @fulfillment
        return ServiceResult.fail("Fulfillment must be processing to ship", code: :invalid_state) unless @fulfillment.processing?
        return ServiceResult.fail("shipping_carrier is required", code: :unprocessable_content) if @shipping_carrier.blank?
        return ServiceResult.fail("tracking_number is required", code: :unprocessable_content) if @tracking_number.blank?

        @fulfillment.with_lock do
          return ServiceResult.fail("Fulfillment must be processing to ship", code: :invalid_state) unless @fulfillment.processing?

          @fulfillment.update!(shipping_carrier: @shipping_carrier, tracking_number: @tracking_number)
          @fulfillment.transition_to!(:shipped)

          AuditLogger.log(
            action: "fulfillment.ship",
            actor: @actor,
            target: @fulfillment,
            payload: {
              from: "processing",
              to: "shipped",
              shipping_carrier: @shipping_carrier,
              tracking_number: @tracking_number,
              auction_settlement_id: @fulfillment.auction_settlement_id
            },
            request: @request
          )

          AppLogger.log(
            event: "admin.fulfillments.ship",
            admin_id: @actor&.id,
            fulfillment_id: @fulfillment.id,
            auction_settlement_id: @fulfillment.auction_settlement_id,
            shipping_carrier: @shipping_carrier
          )

          ServiceResult.ok(code: :shipped, record: @fulfillment)
        end
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :unprocessable_content, record: @fulfillment)
      end
    end
  end
end
