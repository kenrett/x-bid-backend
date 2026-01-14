require Rails.root.join("app/lib/frontend_origins")

Rails.application.config.after_initialize do
  origins = FrontendOrigins.allowed_origin_patterns

  if ActionCable.server
    existing = Array(ActionCable.server.config.allowed_request_origins)
    ActionCable.server.config.allowed_request_origins = (existing + origins).uniq
  end
end
