module CookieDomainResolver
  module_function

  def domain_for(host)
    return nil if Rails.env.test?
    return ".biddersweet.app" if Rails.env.production?
    return ".lvh.me" if Rails.env.development?

    host.to_s.presence
  end
end
