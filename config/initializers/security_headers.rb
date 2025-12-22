# Sets a baseline of security headers for all API responses.
class SecurityHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers ||= {}

    apply_static_headers(headers)
    apply_hsts(headers, env)

    [ status, headers, body ]
  end

  private

  def apply_static_headers(headers)
    static_headers.each do |key, value|
      headers[key] = value
    end
  end

  def apply_hsts(headers, env)
    return unless Rails.env.production?

    request = Rack::Request.new(env)
    return unless request.ssl?

    headers["Strict-Transport-Security"] ||= "max-age=63072000; includeSubDomains; preload"
  end

  def static_headers
    @static_headers ||= {
      "Content-Security-Policy" => "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
      "Referrer-Policy" => "no-referrer",
      "Permissions-Policy" => "geolocation=(), microphone=(), camera=()",
      "X-Content-Type-Options" => "nosniff",
      "Cross-Origin-Opener-Policy" => "same-origin",
      "Cross-Origin-Resource-Policy" => "same-origin"
    }
  end
end
