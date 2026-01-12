require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require_relative "../app/lib/middleware/request_size_limiter"
require_relative "../app/lib/middleware/storefront_context"
# require "rails/test_unit/railtie"
require "rack/deflater"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
require_relative "initializers/security_headers"

module XBidBackend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.autoload_paths << Rails.root.join("app/lib")
    config.autoload_paths << Rails.root.join("app/queries")
    config.eager_load_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/queries")

    config.middleware.use Rack::Attack
    config.middleware.use ActionDispatch::Cookies
    config.middleware.insert_after Rack::Attack, ::SecurityHeaders
    config.middleware.insert_after Rack::Attack, Middleware::RequestSizeLimiter
    # Must run after the executor wraps the request, otherwise Current.* can be reset
    # and storefront_key won't be available to controllers.
    config.middleware.insert_after ActionDispatch::Executor, Middleware::StorefrontContext

    config.middleware.insert_before Rack::Runtime, Rack::Timeout
    unless Rails.env.test?
      config.middleware.insert_after Rack::Timeout, Rack::Deflater, include: [
        "application/json",
        "application/vnd.api+json"
      ]
    end

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
  end
end
