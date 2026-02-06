openapi_runtime_task =
  defined?(Rake) && Rake.application.top_level_tasks.any? { |task| task.start_with?("openapi:") }
openapi_runtime_enabled =
  !Rails.env.production? || ENV["ENABLE_OPENAPI_RUNTIME"].to_s.casecmp("true").zero? || openapi_runtime_task

require Rails.root.join("lib/oas_schemas_runtime") if openapi_runtime_enabled
