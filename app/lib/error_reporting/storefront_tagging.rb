module ErrorReporting
  module StorefrontTagging
    module_function

    # Storefront tagging makes multi-storefront debugging practical by letting error dashboards
    # filter/group issues by `storefront_key` (main/afterdark/marketplace) without changing behavior.
    def set!(storefront_key:)
      key = storefront_key.to_s.presence || "unknown"

      if defined?(Sentry) && Sentry.respond_to?(:configure_scope)
        Sentry.configure_scope { |scope| scope.set_tags(storefront_key: key) }
      end

      if defined?(Honeybadger) && Honeybadger.respond_to?(:context)
        Honeybadger.context(storefront_key: key)
      end
    rescue StandardError
      nil
    end

    def clear!
      if defined?(Sentry) && Sentry.respond_to?(:configure_scope)
        Sentry.configure_scope { |scope| scope.set_tags(storefront_key: "unknown") }
      end

      if defined?(Honeybadger) && Honeybadger.respond_to?(:context)
        Honeybadger.context(storefront_key: "unknown")
      end
    rescue StandardError
      nil
    end
  end
end
