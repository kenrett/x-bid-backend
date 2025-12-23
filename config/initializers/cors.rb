# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

frontend_origins = [
  Rails.application.credentials.frontend_origins&.split(",")
].compact.flatten.map(&:strip).reject(&:empty?)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins frontend_origins.presence || "http://localhost:5173"

    resource "/api/*",
      headers: %w[Authorization Content-Type Accept Origin],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]

    resource "/cable",
      headers: %w[Authorization Origin],
      methods: [ :get, :options ]
  end
end
