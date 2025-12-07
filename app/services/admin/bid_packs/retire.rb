module Admin
  module BidPacks
    class Retire < Admin::BaseCommand
      def initialize(actor:, bid_pack:, request: nil)
        super
      end

      private

      def perform
        if @bid_pack.retired?
          log_outcome(success: false, from: @bid_pack.status, to: @bid_pack.status, errors: [ "Bid pack already retired" ])
          return ServiceResult.fail("Bid pack already retired", code: :invalid_state, record: @bid_pack)
        end

        previous_status = @bid_pack.status

        if @bid_pack.update(status: :retired, active: false)
          AuditLogger.log(action: "bid_pack.delete", actor: @actor, target: @bid_pack, payload: { status: "retired" }, request: @request)
          log_outcome(success: true, from: previous_status, to: @bid_pack.status)
          ServiceResult.ok(code: :retired, message: "Bid pack retired", record: @bid_pack)
        else
          log_outcome(success: false, errors: @bid_pack.errors.full_messages, from: previous_status, to: @bid_pack.status)
          ServiceResult.fail(@bid_pack.errors.full_messages.to_sentence, code: :invalid_bid_pack, record: @bid_pack)
        end
      rescue ActiveRecord::ActiveRecordError => e
        log_exception(e)
        ServiceResult.fail("Unable to retire bid pack", code: :invalid_bid_pack, record: @bid_pack)
      end

      def base_log_context
        {
          event: "admin.bid_packs.retire",
          admin_id: @actor&.id,
          admin_email: @actor&.email_address,
          bid_pack_id: @bid_pack&.id
        }
      end

      def log_outcome(success:, from:, to:, errors: nil)
        AppLogger.log(**base_log_context.merge(success: success, from_status: from, to_status: to, errors: errors&.presence))
      end

      def log_exception(error)
        AppLogger.error(
          event: "admin.bid_packs.retire.error",
          error: error,
          **base_log_context
        )
      end
    end
  end
end
