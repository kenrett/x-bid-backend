# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

require Rails.root.join("app/lib/frontend_origins")

allowed_headers = %w[
  Content-Type
  Authorization
  X-Requested-With
  X-CSRF-Token
].freeze
exposed_headers = %w[Authorization X-Request-Id].freeze
allowed_methods = [ :get, :post, :put, :patch, :delete, :options ].freeze
cable_headers = %w[Authorization Origin].freeze
cable_methods = [ :get, :options ].freeze

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins do |origin, _env|
      FrontendOrigins.allowed_origin?(origin)
    end

    resource "/api/*",
      headers: allowed_headers,
      expose: exposed_headers,
      methods: allowed_methods,
      credentials: true

    resource "/cable",
      headers: cable_headers,
      methods: cable_methods
  end
end

Rails.application.config.middleware.insert_before Rack::Cors, Middleware::RequestDiagnosticsLogger

if %w[production staging].include?(Rails.env)
  begin
    AppLogger.log(
      event: "cors.config",
      origins: FrontendOrigins.allowed_origins,
      credentials: true,
      allowed_headers: allowed_headers,
      allowed_methods: allowed_methods,
      exposed_headers: exposed_headers,
      cable_headers: cable_headers,
      cable_methods: cable_methods
    )
  rescue StandardError => e
    AppLogger.error(event: "cors.config_failed", error: e)
  end
end
