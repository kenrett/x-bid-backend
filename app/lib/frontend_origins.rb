module FrontendOrigins
  module_function

  PROD_SUBDOMAIN_REGEX = %r{\Ahttps://([a-z0-9-]+\.)+biddersweet\.app\z}i
  DEV_SUBDOMAIN_REGEX = %r{\Ahttp://([a-z0-9-]+\.)?lvh\.me(?::\d+)?\z}i

  BIDDERSWEET_ORIGINS = %w[
    https://biddersweet.app
    https://www.biddersweet.app
    https://afterdark.biddersweet.app
    https://marketplace.biddersweet.app
    https://account.biddersweet.app
  ].freeze

  def allowed_origin_patterns(env: Rails.env, credentials: Rails.application.credentials)
    env_key = env.to_s
    env_override = ENV["CORS_ALLOWED_ORIGINS"].to_s.strip
    base_origins = if env_override.present?
      normalize!(env_override.split(",").map(&:strip), env_key)
    else
      for_env!(env, credentials: credentials)
    end

    strings = Array(base_origins) + BIDDERSWEET_ORIGINS
    strings += local_origins if env_key.in?(%w[test development])
    patterns = normalize!(strings.uniq, env_key)

    patterns + wildcard_origin_patterns(env_key)
  end

  def allowed_origins(env: Rails.env, credentials: Rails.application.credentials)
    env_key = env.to_s
    env_override = ENV["CORS_ALLOWED_ORIGINS"].to_s.strip
    base_origins = if env_override.present?
      normalize!(env_override.split(",").map(&:strip), env_key)
    else
      for_env!(env, credentials: credentials)
    end

    allowed = Array(base_origins) + BIDDERSWEET_ORIGINS
    allowed += local_origins if env_key.in?(%w[test development])

    normalize!(allowed.uniq, env_key)
  end

  def allowed_origin?(origin, env: Rails.env, credentials: Rails.application.credentials)
    !allowed_origin_pattern_match(origin, env: env, credentials: credentials).nil?
  rescue StandardError
    false
  end

  def for_env!(env = Rails.env, credentials: Rails.application.credentials)
    env_key = env.to_s

    env_override = ENV["FRONTEND_ORIGINS"].to_s.strip
    if env_override.present?
      origins = env_override.split(",").map(&:strip)
      return normalize!(origins, env_key)
    end

    value = credentials.respond_to?(:frontend_origins) ? credentials.frontend_origins : nil
    unless value.is_a?(Hash)
      return default_for(env_key) if env_key.in?(%w[test development]) || ENV["CI"].present?

      raise "credentials.frontend_origins must be a Hash keyed by environment (e.g. development/production) or set FRONTEND_ORIGINS"
    end

    origins = value[env_key] || value[env_key.to_sym]
    origins = value["development"] || value[:development] if origins.nil? && env_key == "test"
    unless origins.is_a?(Array)
      raise "credentials.frontend_origins.#{env} must be an Array of absolute origin URLs"
    end

    normalize!(origins, env_key)
  end

  def normalize!(origins, env_key)
    normalized = Array(origins)
      .map { |origin| origin.to_s.strip.delete_suffix("/") }
      .reject(&:blank?)

    raise "frontend origins for #{env_key} must include at least one origin" if normalized.empty?

    invalid = normalized.reject { |origin| origin.start_with?("http://", "https://") }
    raise "Invalid frontend origin(s) for #{env_key}: #{invalid.join(", ")}" if invalid.any?

    normalized
  end

  def local_origins
    %w[
      http://localhost:5173
      http://afterdark.localhost:5173
      http://marketplace.localhost:5173
      http://account.localhost:5173
      http://main.lvh.me:5173
      http://afterdark.lvh.me:5173
      http://artisan.lvh.me:5173
      http://lvh.me:5173
    ]
  end

  def default_for(env_key)
    return local_origins if env_key.in?(%w[test development])

    []
  end

  def allowed_origin_pattern_match(origin, env: Rails.env, credentials: Rails.application.credentials)
    return nil if origin.to_s.strip.empty?

    normalized = RequestDiagnostics.normalize_origin(origin)
    allowed_origin_patterns(env: env, credentials: credentials).find do |pattern|
      pattern.is_a?(Regexp) ? normalized.match?(pattern) : normalized == pattern
    end
  rescue StandardError
    nil
  end

  def wildcard_origin_patterns(env_key)
    if env_key == "production"
      [ PROD_SUBDOMAIN_REGEX ]
    elsif env_key.in?(%w[test development])
      [ DEV_SUBDOMAIN_REGEX ]
    else
      []
    end
  end
end
