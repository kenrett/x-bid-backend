module Storefront
  class Resolver
    CANONICAL_KEYS = StorefrontKeyable::CANONICAL_KEYS
    DEFAULT_KEY = StorefrontKeyable::DEFAULT_KEY

    def self.resolve(request)
      header_value = request.headers["X-Storefront-Key"].to_s.strip.downcase
      if header_value.present?
        if CANONICAL_KEYS.include?(header_value)
          return header_value
        end

        fallback_key = resolve_from_host(extract_host(request)) || DEFAULT_KEY
        log_invalid_header_key(request: request, invalid_key: header_value, resolved_to: fallback_key)
        return fallback_key
      end

      resolve_from_host(extract_host(request)) || DEFAULT_KEY
    end

    def self.resolve_for_log(request)
      header_value = request.headers["X-Storefront-Key"].to_s.strip.downcase
      if header_value.present?
        return header_value if CANONICAL_KEYS.include?(header_value)

        return resolve_from_host(extract_host(request)) || DEFAULT_KEY
      end

      resolve_from_host(extract_host(request)) || DEFAULT_KEY
    end

    def self.resolve_from_host(host)
      normalized = host.to_s.strip.downcase
      return DEFAULT_KEY if normalized.blank?

      return "afterdark" if normalized.start_with?("afterdark.")
      return "marketplace" if normalized.start_with?("marketplace.")

      DEFAULT_KEY
    end

    def self.extract_host(request)
      forwarded = request.headers["X-Forwarded-Host"].to_s
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
        .last

      raw = forwarded.presence || request.get_header("HTTP_HOST").to_s
      host = raw.to_s.strip.downcase
      host = host.split(":").first if host.include?(":")
      host.presence || request.host.to_s
    end

    def self.log_invalid_header_key(request:, invalid_key:, resolved_to:)
      AppLogger.log(
        event: "storefront.resolve.invalid_header_key",
        level: :warn,
        invalid_key: invalid_key,
        resolved_to: resolved_to,
        request_id: request.request_id,
        host: request.host,
        path: request.fullpath,
        user_id: Current.user_id
      )
    end
  end
end
