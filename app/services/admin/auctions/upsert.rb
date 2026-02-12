module Admin
  module Auctions
    class Upsert < Admin::BaseCommand
      def initialize(actor:, auction: nil, attrs:, request: nil)
        auction ||= ::Auction.new
        auction.storefront_key ||= Current.storefront_key.to_s.presence
        normalized_attrs = normalize_status(attrs)
        super(actor: actor, auction: auction, attrs: normalized_attrs, request: request)
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
        value = @attrs[key]
        return true if ::Auctions::Status.from_api(value).present?
        return true if ::Auction.statuses.key?(value.to_s)

        false
      end

      def normalize_status(attrs)
        return attrs unless attrs.respond_to?(:to_h)
        hash = attrs.to_h
        return hash unless hash.key?("status") || hash.key?(:status)

        key = hash.key?("status") ? "status" : :status
        mapped = ::Auctions::Status.from_api(hash[key])
        mapped ? hash.merge(key => mapped) : hash
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
        return if desired_status.to_s == @auction.status.to_s

        desired = desired_status.to_s
        current = @auction.status.to_s

        case desired
        when "pending"
          unless @auction.new_record? || @auction.pending? || @auction.inactive?
            raise_invalid_transition!(from: current, to: desired)
          end
          @auction.schedule!(starts_at: @auction.start_date, ends_at: @auction.end_time)
        when "active"
          raise_invalid_transition!(from: current, to: desired) unless @auction.pending?
          @auction.start!
        when "ended"
          raise_invalid_transition!(from: current, to: desired) unless @auction.active?
          @auction.close!
        when "cancelled"
          unless @auction.pending? || @auction.active?
            raise_invalid_transition!(from: current, to: desired)
          end
          @auction.cancel!
        when "inactive"
          @auction.retire!
        else
          raise ::Auction::InvalidState, "Unsupported status: #{desired_status}"
        end
      end

      def raise_invalid_transition!(from:, to:)
        raise ::Auction::InvalidState, "Cannot transition auction from #{::Auctions::Status.to_api(from)} to #{::Auctions::Status.to_api(to)}"
      end
    end
  end
end
