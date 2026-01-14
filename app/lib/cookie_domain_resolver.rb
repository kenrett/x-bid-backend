module CookieDomainResolver
  module_function

  def domain_for(host)
    env_override = ENV["SESSION_COOKIE_DOMAIN"].to_s.strip
    if env_override.present?
      host_value = host.to_s
      override_host = env_override.delete_prefix(".")
      return env_override if host_value.end_with?(override_host)
    end
    return nil if Rails.env.test?
    host_value = host.to_s
    return ".lvh.me" if host_value.end_with?("lvh.me")
    return ".biddersweet.app" if host_value.end_with?("biddersweet.app")

    nil
  end

  def same_site
    env_override = ENV["COOKIE_SAMESITE"].to_s.strip.downcase
    return :none if env_override == "none"
    return :strict if env_override == "strict"
    return :lax if env_override == "lax"

    :lax
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
