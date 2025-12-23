# Sets a baseline of security headers for all API responses.
require "securerandom"

class SecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers ||= {}

    script_nonce = SecureRandom.base64(16)
    expose_nonce_to_rails(env, script_nonce)

    apply_static_headers(headers, script_nonce)
    apply_hsts(headers, env)

    [ status, headers, body ]
  end

  private

  def expose_nonce_to_rails(env, script_nonce)
    env[ActionDispatch::ContentSecurityPolicy::Request::NONCE] = script_nonce
    env[ActionDispatch::ContentSecurityPolicy::Request::NONCE_GENERATOR] = ->(_request) { script_nonce }
  end

  def apply_static_headers(headers, script_nonce)
    static_headers(script_nonce).each do |key, value|
      headers[key] = value
    end
  end

  def apply_hsts(headers, env)
    return unless Rails.env.production?

    request = Rack::Request.new(env)
    return unless request.ssl?

    headers["Strict-Transport-Security"] ||= "max-age=63072000; includeSubDomains; preload"
  end

  def static_headers(script_nonce)
    script_sources = [
      "'self'",
      "https://js.stripe.com",
      "https://static.cloudflareinsights.com",
      "'nonce-#{script_nonce}'"
    ].join(" ")

    connect_sources = [
      "'self'",
      "https://cloudflareinsights.com"
    ].join(" ")

    {
      "Content-Security-Policy" => [
        "default-src 'self'",
        "script-src #{script_sources}",
        "connect-src #{connect_sources}",
        "frame-ancestors 'none'",
        "base-uri 'none'",
        "form-action 'self'"
      ].join("; "),
      "Referrer-Policy" => "no-referrer",
      "Permissions-Policy" => "geolocation=(), microphone=(), camera=()",
      "X-Content-Type-Options" => "nosniff",
      "Cross-Origin-Opener-Policy" => "same-origin",
      "Cross-Origin-Resource-Policy" => "same-origin"
    }
  end
end
