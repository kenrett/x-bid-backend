module Middleware
  class StorefrontContext
    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)
      storefront_key = Storefront::Resolver.resolve(request)
      Current.storefront_key = storefront_key
      ErrorReporting::StorefrontTagging.set!(storefront_key: storefront_key)

      # TODO: hook policy enforcement based on `Current.storefront_key` here.

      logger = Rails.logger
      if logger.respond_to?(:tagged)
        logger.tagged("storefront=#{storefront_key}") { @app.call(env) }
      else
        @app.call(env)
      end
    ensure
      ErrorReporting::StorefrontTagging.clear!
      Current.storefront_key = nil
    end
  end
end
