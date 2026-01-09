module Jobs
  module WithStorefrontContext
    extend ActiveSupport::Concern

    CANONICAL_KEYS = StorefrontKeyable::CANONICAL_KEYS.freeze
    DEFAULT_KEY = StorefrontKeyable::DEFAULT_KEY

    private

    def with_storefront_context(storefront_key:)
      resolved_key = sanitize_storefront_key(storefront_key)
      Current.storefront_key = resolved_key
      ErrorReporting::StorefrontTagging.set!(storefront_key: resolved_key) if defined?(ErrorReporting::StorefrontTagging)

      AppLogger.log(
        event: "jobs.storefront.context",
        storefront_key: resolved_key,
        job_class: self.class.name,
        job_id: job_id,
        request_id: Current.request_id
      )

      if Rails.logger.respond_to?(:tagged)
        tags = [ "storefront=#{resolved_key}", "job=#{job_id}" ]
        Rails.logger.tagged(*tags) { yield }
      else
        yield
      end
    ensure
      ErrorReporting::StorefrontTagging.clear! if defined?(ErrorReporting::StorefrontTagging)
      Current.storefront_key = nil
    end

    def sanitize_storefront_key(proposed_key)
      normalized = proposed_key.to_s.strip
      return normalized if CANONICAL_KEYS.include?(normalized)

      AppLogger.log(
        event: "jobs.storefront.invalid_key",
        level: :warn,
        invalid_key: proposed_key,
        job_class: self.class.name,
        job_id: job_id,
        defaulted_to: DEFAULT_KEY
      )

      DEFAULT_KEY
    end
  end
end
