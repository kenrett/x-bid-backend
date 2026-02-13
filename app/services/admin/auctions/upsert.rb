module Admin
  module Auctions
    class Upsert < Admin::BaseCommand
      def initialize(actor:, auction: nil, attrs:, request: nil)
        auction ||= ::Auction.new
        auction.storefront_key ||= Current.storefront_key.to_s.presence
        super(actor: actor, auction: auction, attrs: attrs, request: request)
      end

      def perform
        return ServiceResult.fail("Invalid status. Allowed: #{::Auctions::Status.allowed_keys.join(', ')}", code: :invalid_status) unless valid_status?

        ActiveRecord::Base.transaction do
          apply_details!
          apply_status_transition!
        end

        AuditLogger.log(action: action_name, actor: @actor, target: @auction, payload: @attrs, request: @request)
        ::Auctions::Events::ListBroadcast.call(auction: @auction)
        ServiceResult.ok(code: action_result_code, message: "Auction #{action_result_code == :created ? 'created' : 'updated'}", record: @auction, data: { auction: @auction })
      rescue ::Auction::InvalidState => e
        ServiceResult.fail(e.message, code: :invalid_state, record: @auction)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.fail(@auction.errors.full_messages.to_sentence, code: :invalid_auction, record: @auction)
      end

      def action_name
        @auction.persisted? ? "auction.update" : "auction.create"
      end

      def valid_status?
        return true unless @attrs&.key?("status") || @attrs&.key?(:status)

        key = @attrs.key?("status") ? "status" : :status
        ::Auctions::Status.to_internal(@attrs[key]).present?
      end

      def apply_details!
        detail_attrs = @attrs.except(:status, "status").compact
        return if detail_attrs.empty?

        normalize_image_url!(detail_attrs)
        @auction.update_details!(detail_attrs)
      end

      def normalize_image_url!(detail_attrs)
        key = if detail_attrs.key?(:image_url)
          :image_url
        elsif detail_attrs.key?("image_url")
          "image_url"
        end
        return unless key

        detail_attrs[key] = Uploads::ImageUrl.stable(detail_attrs[key])
      end

      def action_result_code
        @auction.previous_changes["id"] ? :created : :ok
      end

      def apply_status_transition!
        desired_status = @attrs[:status] || @attrs["status"]
        return unless desired_status
        @auction.transition_to!(desired_status)
      end
    end
  end
end
