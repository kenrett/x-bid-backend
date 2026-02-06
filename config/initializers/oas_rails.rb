openapi_runtime_task =
  defined?(Rake) && Rake.application.top_level_tasks.any? { |task| task.start_with?("openapi:") }
openapi_runtime_enabled =
  !Rails.env.production? || ENV["ENABLE_OPENAPI_RUNTIME"].to_s.casecmp("true").zero? || openapi_runtime_task

if openapi_runtime_enabled
  OasRails.configure do |config|
    # API metadata
    config.info.title = "XBid API"
    config.info.version = "1.0.0"
    config.info.summary = "Interactive docs for the XBid backend"
    config.info.description = <<~DESC
      REST API for the XBid auction platform. Endpoints cover authentication,
      auctions, bidding, bid packs, payments, maintenance mode, and admin tools.
    DESC

    # Servers used by RapiDoc's "Try" feature. Override via OAS_SERVER_URL/APP_URL.
    config.servers = [
      {
        url: ENV.fetch("OAS_SERVER_URL", ENV.fetch("APP_URL", "http://localhost:3000")),
        description: "Default server"
      }
    ]

    # Use bearer JWT auth and require auth by default (override per-action with @no_auth).
    config.security_schema = :bearer_jwt
    config.authenticate_all_routes_by_default = true

    # Scope API path generation (leave root because engine is mounted at /api-docs).
    config.api_path = "/"

    # RapiDoc UI tweaks to keep the Try button enabled.
    config.rapidoc_configuration = {
      allow_try: true
    }
  end
end
