if ENV.fetch("PROCESS_ROLE", "web") == "web"
  require Rails.root.join("app/lib/frontend_origins")

  Rails.application.config.after_initialize do
    origins = FrontendOrigins.allowed_origin_patterns

    if ActionCable.server
      ActionCable.server.config.allowed_request_origins = origins
    end
  end
end
