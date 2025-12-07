module Admin
  module Auctions
    class Upsert < Admin::BaseCommand
      def initialize(actor:, auction: nil, attrs:, request: nil)
        auction ||= ::Auction.new
        normalized_attrs = normalize_status(attrs)
        super(actor: actor, auction: auction, attrs: normalized_attrs, request: request)
      end

      def perform
        return ServiceResult.fail("Invalid status. Allowed: #{::Auctions::Status.allowed_keys.join(', ')}") unless valid_status?

        if @auction.update(@attrs)
          AuditLogger.log(action: action_name, actor: @actor, target: @auction, payload: @attrs, request: @request)
          ServiceResult.ok(record: @auction)
        else
          ServiceResult.fail(@auction.errors.full_messages.to_sentence)
        end
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
    end
  end
end
