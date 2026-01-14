module CookieDomainResolver
  module_function

  def domain_for(host)
    env_override = ENV["SESSION_COOKIE_DOMAIN"].to_s.strip
    return env_override if env_override.present?
    return nil if Rails.env.test?
    return ".biddersweet.app" if Rails.env.production?
    if Rails.env.development?
      host_value = host.to_s
      return ".lvh.me" if host_value.end_with?("lvh.me")

      return nil if host_value.end_with?("localhost")
    end

    host.to_s.presence
  end
end
