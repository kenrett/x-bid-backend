module Admin
  module Fulfillments
    class Process < Admin::BaseCommand
      def initialize(actor:, fulfillment:, shipping_cost_cents:, notes: nil, request: nil)
        super(actor: actor, fulfillment: fulfillment, shipping_cost_cents: shipping_cost_cents, notes: notes, request: request)
      end

      private

      def perform
        return ServiceResult.fail("Fulfillment not provided", code: :invalid_fulfillment) unless @fulfillment
        return ServiceResult.fail("Fulfillment must be claimed to process", code: :invalid_state) unless @fulfillment.claimed?

        shipping_cost_cents = normalize_shipping_cost_cents(@shipping_cost_cents)
        return ServiceResult.fail("shipping_cost_cents is required", code: :invalid_amount) if shipping_cost_cents.nil?
        return ServiceResult.fail("shipping_cost_cents must be non-negative", code: :invalid_amount) if shipping_cost_cents.negative?

        @fulfillment.with_lock do
          return ServiceResult.fail("Fulfillment must be claimed to process", code: :invalid_state) unless @fulfillment.claimed?

          @fulfillment.update!(
            shipping_cost_cents: shipping_cost_cents,
            metadata: updated_metadata_for(@fulfillment.metadata, notes: @notes)
          )
          @fulfillment.transition_to!(:processing)

          AuditLogger.log(
            action: "fulfillment.process",
            actor: @actor,
            target: @fulfillment,
            payload: {
              from: "claimed",
              to: "processing",
              shipping_cost_cents: shipping_cost_cents,
              notes_present: @notes.present?,
              auction_settlement_id: @fulfillment.auction_settlement_id
            },
            request: @request
          )

          AppLogger.log(
            event: "admin.fulfillments.process",
            admin_id: @actor&.id,
            fulfillment_id: @fulfillment.id,
            auction_settlement_id: @fulfillment.auction_settlement_id,
            shipping_cost_cents: shipping_cost_cents
          )

          ServiceResult.ok(code: :processing, record: @fulfillment)
        end
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :unprocessable_content, record: @fulfillment)
      end

      def normalize_shipping_cost_cents(value)
        return value if value.is_a?(Integer)
        return nil if value.blank?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def updated_metadata_for(existing, notes:)
        base = (existing || {}).deep_dup
        return base unless notes.present?

        admin_notes = base["admin_notes"]
        admin_notes = {} unless admin_notes.is_a?(Hash)
        admin_notes["processing"] = notes.to_s
        base["admin_notes"] = admin_notes
        base
      end
    end
  end
end
