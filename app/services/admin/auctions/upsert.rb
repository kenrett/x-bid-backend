module Admin
  module Auctions
    class Upsert < Admin::BaseCommand
      MARKETPLACE_STOREFRONT = "marketplace".freeze
      ADULT_STOREFRONT = "afterdark".freeze
      MAIN_STOREFRONT = "main".freeze
      STOREFRONT_FLAG_MAP = {
        MAIN_STOREFRONT => { is_marketplace: false, is_adult: false }.freeze,
        ADULT_STOREFRONT => { is_marketplace: false, is_adult: true }.freeze,
        MARKETPLACE_STOREFRONT => { is_marketplace: true, is_adult: false }.freeze
      }.freeze

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
        ServiceResult.fail(
          @auction.errors.full_messages.to_sentence,
          code: :invalid_auction,
          record: @auction,
          data: { field_errors: @auction.errors.messages }
        )
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
        provided_storefront_key = detail_attrs[:storefront_key]
        storefront_from_legacy_flags = derive_storefront_from_legacy_flags(detail_attrs)
        using_explicit_storefront_key = detail_attrs.key?(:storefront_key)

        normalized_storefront = if using_explicit_storefront_key
          normalize_storefront_key(provided_storefront_key)
        elsif storefront_from_legacy_flags.present?
          storefront_from_legacy_flags
        else
          normalize_storefront_key(@auction.storefront_key)
        end

        if using_explicit_storefront_key && normalized_storefront.nil?
          invalidate_auction_field!(
            :storefront_key,
            "must be one of: #{StorefrontKeyable::CANONICAL_KEYS.join(', ')}"
          )
        end

        return unless normalized_storefront
        ensure_storefront_reassignment_allowed!(normalized_storefront)

        detail_attrs[:storefront_key] = normalized_storefront
        storefront_flags = STOREFRONT_FLAG_MAP.fetch(normalized_storefront)
        detail_attrs[:is_marketplace] = storefront_flags.fetch(:is_marketplace)
        detail_attrs[:is_adult] = storefront_flags.fetch(:is_adult)
      end

      def normalize_storefront_key(value)
        key = value.to_s.strip.downcase
        return nil if key.blank?
        return key if StorefrontKeyable::CANONICAL_KEYS.include?(key)

        nil
      end

      def derive_storefront_from_legacy_flags(detail_attrs)
        return nil unless detail_attrs.key?(:is_adult) || detail_attrs.key?(:is_marketplace)

        is_marketplace = ActiveModel::Type::Boolean.new.cast(detail_attrs[:is_marketplace])
        is_adult = ActiveModel::Type::Boolean.new.cast(detail_attrs[:is_adult])

        if is_marketplace && is_adult
          invalidate_auction_field!(:storefront_key, "cannot map legacy flags where both is_adult and is_marketplace are true")
        end

        return MARKETPLACE_STOREFRONT if is_marketplace
        return ADULT_STOREFRONT if is_adult

        MAIN_STOREFRONT
      end

      def ensure_storefront_reassignment_allowed!(normalized_storefront)
        previous_storefront = @auction.storefront_key.to_s
        return if previous_storefront.blank?
        return if previous_storefront == normalized_storefront
        return unless @auction.persisted?
        return unless @auction.bids.exists?

        invalidate_auction_field!(:storefront_key, "cannot be reassigned after bids have been placed")
      end

      def invalidate_auction_field!(field, message)
        @auction.errors.add(field, message)
        raise ActiveRecord::RecordInvalid.new(@auction)
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
