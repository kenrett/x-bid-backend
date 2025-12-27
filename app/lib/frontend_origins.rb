module FrontendOrigins
  module_function

  def for_env!(env = Rails.env, credentials: Rails.application.credentials)
    value = credentials.frontend_origins
    unless value.is_a?(Hash)
      raise "credentials.frontend_origins must be a Hash keyed by environment (e.g. development/production)"
    end

    env_key = env.to_s
    origins = value[env_key] || value[env_key.to_sym]
    origins = value["development"] || value[:development] if origins.nil? && env_key == "test"
    unless origins.is_a?(Array)
      raise "credentials.frontend_origins.#{env} must be an Array of absolute origin URLs"
    end

    normalized = origins
      .map { |origin| origin.to_s.strip.delete_suffix("/") }
      .reject(&:blank?)

    raise "credentials.frontend_origins.#{env} must include at least one origin" if normalized.empty?

    invalid = normalized.reject { |origin| origin.start_with?("http://", "https://") }
    raise "Invalid frontend origin(s) for #{env}: #{invalid.join(", ")}" if invalid.any?

    normalized
  end
end
