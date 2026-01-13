# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

require Rails.root.join("app/lib/frontend_origins")

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*FrontendOrigins.allowed_origins)

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
