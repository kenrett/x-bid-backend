module Storefront
  class Resolver
    CANONICAL_KEYS = %w[main afterdark artisan].freeze
    DEFAULT_KEY = "main"

    HOST_MAPPING = {
      "biddersweet.app" => "main",
      "www.biddersweet.app" => "main",
      "afterdark.biddersweet.app" => "afterdark",
      "artisan.biddersweet.app" => "artisan"
    }.freeze

    def self.resolve(request)
      header_value = request.headers["X-Storefront-Key"].to_s.strip.downcase
      if header_value.present?
        return header_value if CANONICAL_KEYS.include?(header_value)

        log_invalid_header_key(request: request, invalid_key: header_value)
        return DEFAULT_KEY
      end

      host_key = resolve_from_host(extract_host(request))
      return host_key if host_key

      DEFAULT_KEY
    end

    def self.resolve_from_host(host)
      normalized = host.to_s.strip.downcase
      return DEFAULT_KEY if normalized.blank?

      mapped = HOST_MAPPING[normalized]
      return mapped if mapped

      if normalized.end_with?(".localhost")
        subdomain = normalized.delete_suffix(".localhost").split(".").first
        return subdomain if CANONICAL_KEYS.include?(subdomain)
      end

      DEFAULT_KEY if %w[localhost 127.0.0.1 0.0.0.0].include?(normalized)
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

    def self.log_invalid_header_key(request:, invalid_key:)
      logger = Rails.logger
      message = [
        "storefront.resolve.invalid_header_key",
        "invalid_key=#{invalid_key.inspect}",
        "resolved_to=#{DEFAULT_KEY}",
        "host=#{request.host.to_s.inspect}",
        "path=#{request.fullpath.to_s.inspect}",
        "request_id=#{request.request_id.to_s.inspect}"
      ].join(" ")

      if logger.respond_to?(:tagged)
        logger.tagged("storefront=#{DEFAULT_KEY}") { logger.warn(message) }
      else
        logger.warn(message)
      end
    end
  end
end
