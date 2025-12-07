module Admin
  module BidPacks
    class Upsert < Admin::BaseCommand
      def initialize(actor:, bid_pack: nil, attrs:, request: nil)
        bid_pack ||= ::BidPack.new
        normalized_attrs = attrs.respond_to?(:to_h) ? attrs.to_h : attrs
        super(actor: actor, bid_pack: bid_pack, attrs: normalized_attrs, request: request)
      end

      private

      def perform
        @bid_pack.assign_attributes(@attrs)

        if @bid_pack.save
          AuditLogger.log(action: action_name, actor: @actor, target: @bid_pack, payload: @attrs, request: @request)
          log_outcome(success: true, changes: change_summary)
          return ServiceResult.ok(code: result_code, message: success_message, record: @bid_pack)
        end

        log_outcome(success: false, errors: @bid_pack.errors.full_messages)
        ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence, code: :invalid_bid_pack, record: @bid_pack)
      rescue ArgumentError => e
        log_outcome(success: false, errors: [ e.message ])
        ServiceResult.fail("Invalid status", code: :invalid_status, record: @bid_pack)
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to save bid pack", code: :invalid_bid_pack, record: @bid_pack)
      end

      def action_name
        @bid_pack.persisted? ? "bid_pack.update" : "bid_pack.create"
      end

      def result_code
        @bid_pack.previous_changes["id"] ? :created : :ok
      end

      def success_message
        @bid_pack.previous_changes["id"] ? "Bid pack created" : "Bid pack updated"
      end

      def change_summary
        return {} unless @bid_pack.saved_changes

        @bid_pack.saved_changes.except("created_at", "updated_at").transform_values do |(before, after)|
          { before: before, after: after }
        end
      end

      def base_log_context
        {
          event: "admin.bid_packs.upsert",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          bid_pack_id: @bid_pack&.id
        }
      end

      def log_outcome(success:, changes: nil, errors: nil)
        AppLogger.log(**base_log_context.merge(success: success, changes: changes&.presence, errors: errors&.presence))
      end

      def log_exception(error)
        AppLogger.error(
          event: "admin.bid_packs.upsert.error",
          error: error,
          **base_log_context
        )
      end
    end
  end
end
