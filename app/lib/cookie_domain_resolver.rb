module CookieDomainResolver
  module_function

  def domain_for(host)
    env_override = ENV["SESSION_COOKIE_DOMAIN"].to_s.strip
    if env_override.present?
      host_value = host.to_s
      override_host = env_override.delete_prefix(".")
      allow_override = env_override != ".biddersweet.app" || Rails.env.production?
      return env_override if allow_override && host_value.end_with?(override_host)
    end
    return nil if Rails.env.test?
    host_value = host.to_s
    return ".lvh.me" if host_value.end_with?("lvh.me")
    # Share cookies across biddersweet.app subdomains (api, afterdark, etc).
    return ".biddersweet.app" if Rails.env.production? && host_value.end_with?("biddersweet.app")

    nil
  end

  def same_site
    env_override = ENV["SESSION_COOKIE_SAMESITE"].presence || ENV["COOKIE_SAMESITE"].presence
    env_value = env_override.to_s.strip.downcase
    return :strict if env_value == "strict"
    return :lax if env_value == "lax"
    return :none if env_value == "none" && allow_same_site_none?

    :lax
  end

  def allow_same_site_none?
    raw_value = ENV["ALLOW_SAMESITE_NONE"].to_s.strip.downcase
    raw_value == "true" || raw_value == "1" || raw_value == "yes"
  end

  def secure?(same_site_value = same_site)
    return true if Rails.env.production? && same_site_value == :none

    Rails.env.production?
  end

  def cookie_options(host, path: "/")
    same_site_value = same_site
    {
      domain: domain_for(host),
      same_site: same_site_value,
      secure: secure?(same_site_value),
      path: path
    }
  end
end
