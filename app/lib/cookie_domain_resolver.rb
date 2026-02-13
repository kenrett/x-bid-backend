module CookieDomainResolver
  module_function

  def domain_for(_host)
    # Session cookies are host-only to prevent subdomains from receiving auth cookies.
    nil
  end

  def legacy_domain_for(host)
    host_value = host.to_s
    return ".biddersweet.app" if host_value.end_with?("biddersweet.app")
    return ".lvh.me" if host_value.end_with?("lvh.me")

    nil
  end

  def same_site
    env_override = ENV["SESSION_COOKIE_SAMESITE"].presence || ENV["COOKIE_SAMESITE"].presence
    env_value = env_override.to_s.strip.downcase
    return :strict if env_value == "strict"

    :lax
  end

  def secure?(_same_site_value = same_site)
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
