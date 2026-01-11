# Ensure Action Cable accepts connections from local development subdomains.
if Rails.env.development?
  require Rails.root.join("app/lib/frontend_origins")

  Rails.application.config.after_initialize do
    # Add local origins to the Action Cable configuration
    origins = FrontendOrigins.local_origins

    # Update the server config directly if it's already initialized
    if ActionCable.server
      existing = Array(ActionCable.server.config.allowed_request_origins)
      ActionCable.server.config.allowed_request_origins = (existing + origins).uniq
    end
  end
end
