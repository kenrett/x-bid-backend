module FrontendOrigins
  module_function

  PROD_SUBDOMAIN_REGEX = %r{\Ahttps://([a-z0-9-]+\.)+biddersweet\.app\z}i
  DEV_SUBDOMAIN_REGEX = %r{\Ahttp://([a-z0-9-]+\.)*lvh\.me:5173\z}i

  BIDDERSWEET_ORIGINS = %w[
    https://biddersweet.app
    https://afterdark.biddersweet.app
    https://marketplace.biddersweet.app
    https://account.biddersweet.app
  ].freeze

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
    return false if origin.to_s.strip.empty?

    normalized = RequestDiagnostics.normalize_origin(origin)
    return true if wildcard_origin_allowed?(normalized, env: env)
    allowed_origins(env: env, credentials: credentials).include?(normalized)
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
      http://lvh.me:5173
    ]
  end

  def default_for(env_key)
    return local_origins if env_key.in?(%w[test development])

    []
  end

  def wildcard_origin_allowed?(origin, env: Rails.env)
    env_key = env.to_s
    return true if env_key == "production" && origin.match?(PROD_SUBDOMAIN_REGEX)
    return true if env_key.in?(%w[test development]) && origin.match?(DEV_SUBDOMAIN_REGEX)

    false
  end
end
