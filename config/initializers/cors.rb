# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

require Rails.root.join("app/lib/frontend_origins")

frontend_origins = FrontendOrigins.for_env!

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    biddersweet_origins = %w[
      https://biddersweet.app
      https://afterdark.biddersweet.app
      https://marketplace.biddersweet.app
      https://account.biddersweet.app
    ]

    local_origins = %w[
      http://localhost:5173
      http://afterdark.localhost:5173
      http://marketplace.localhost:5173
      http://account.localhost:5173
    ]

    allowed_origins = Array(frontend_origins) + biddersweet_origins
    allowed_origins += local_origins if Rails.env.development? || Array(frontend_origins).empty?

    origins(*allowed_origins.uniq)

    resource "/api/*",
      headers: %w[Authorization Content-Type Accept Origin X-Storefront-Key],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]

    resource "/cable",
      headers: %w[Authorization Origin],
      methods: [ :get, :options ]
  end
end
