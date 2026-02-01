if Rails.env.production?
  required_env_vars = %w[
    S3_BUCKET
    AWS_REGION
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
  ]

  missing = required_env_vars.select { |key| ENV[key].to_s.strip.empty? }

  if missing.any?
    raise <<~ERROR
      Active Storage S3 is required in production, but the following environment variables are missing:
      #{missing.join(", ")}

      Set the required values in your deployment environment. Example:
      S3_BUCKET=your-bucket
      AWS_REGION=us-east-1
      AWS_ACCESS_KEY_ID=...
      AWS_SECRET_ACCESS_KEY=...
    ERROR
  end
end
