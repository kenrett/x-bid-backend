# Fail fast if critical environment variables are missing in production
if Rails.env.production?
  required_env_vars = [
    "SECRET_KEY_BASE",
    "DATABASE_URL",
    "REDIS_URL"
  ]

  required_env_vars.each do |env_var|
    next if ENV[env_var].present?

    message = "#{env_var} environment variable is missing. Application cannot start."
    Rails.logger.fatal(message)
    raise message
  end
end
