module Admin
  module Auctions
    class Upsert < Admin::BaseCommand
      MARKETPLACE_STOREFRONT = "marketplace".freeze
      ADULT_STOREFRONT = "afterdark".freeze

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
        detail_attrs = @attrs.except(:status, "status").compact.symbolize_keys
        normalize_catalog_flags!(detail_attrs)
        return if detail_attrs.empty?

        normalize_image_url!(detail_attrs)
        @auction.update_details!(detail_attrs)
      end

      def normalize_image_url!(detail_attrs)
        return unless detail_attrs.key?(:image_url)

        detail_attrs[:image_url] = Uploads::ImageUrl.stable(detail_attrs[:image_url])
      end

      def normalize_catalog_flags!(detail_attrs)
        storefront_key = detail_attrs[:storefront_key].presence || @auction.storefront_key.to_s.presence
        normalized_storefront = normalize_storefront_key(storefront_key)
        return unless normalized_storefront

        detail_attrs[:storefront_key] = normalized_storefront if detail_attrs.key?(:storefront_key)
        detail_attrs[:is_marketplace] = normalized_storefront == MARKETPLACE_STOREFRONT
        detail_attrs[:is_adult] = false unless normalized_storefront == ADULT_STOREFRONT
      end

      def normalize_storefront_key(value)
        key = value.to_s.strip.downcase
        return nil if key.blank?
        return key if StorefrontKeyable::CANONICAL_KEYS.include?(key)

        nil
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
