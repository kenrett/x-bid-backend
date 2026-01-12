# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

require Rails.root.join("app/lib/frontend_origins")

frontend_origins = FrontendOrigins.for_env!
env_override = ENV["CORS_ALLOWED_ORIGINS"].to_s.strip

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    biddersweet_origins = %w[
      https://biddersweet.app
      https://afterdark.biddersweet.app
      https://marketplace.biddersweet.app
      https://account.biddersweet.app
    ]

    allowed_origins = Array(frontend_origins) + biddersweet_origins
    allowed_origins += FrontendOrigins.local_origins if Rails.env.development? || Array(frontend_origins).empty?
    if env_override.present?
      allowed_origins = env_override.split(",").map(&:strip)
    end

    origins(*allowed_origins.uniq)

    resource "/api/*",
      headers: %w[Origin Content-Type Accept Authorization X-Requested-With X-CSRF-Token X-Storefront-Key],
      expose: %w[Authorization X-Request-Id],
      methods: [ :get, :post, :put, :patch, :delete, :options ],
      credentials: true

    resource "/cable",
      headers: %w[Authorization Origin],
      methods: [ :get, :options ]
  end
end
