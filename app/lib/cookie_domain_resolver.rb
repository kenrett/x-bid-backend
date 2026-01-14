module CookieDomainResolver
  module_function

  def domain_for(host)
    env_override = ENV["SESSION_COOKIE_DOMAIN"].to_s.strip
    return env_override if env_override.present?
    return nil if Rails.env.test?
    return ".biddersweet.app" if Rails.env.production?
    return ".lvh.me" if Rails.env.development?

    host.to_s.presence
  end
end
