# Fail fast if critical environment variables are missing in production
if Rails.env.production?
  if ENV["DATABASE_URL"].blank?
    message = "DATABASE_URL environment variable is missing. Application cannot start."
    Rails.logger.fatal(message)
    raise message
  end

  if ENV["REDIS_URL"].blank?
    message = "REDIS_URL environment variable is missing. Application cannot start."
    Rails.logger.fatal(message)
    raise message
  end
end
