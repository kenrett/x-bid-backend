module Api
  module V1
    class CsrfController < ApplicationController
      # GET /api/v1/csrf
      # @summary Returns CSRF token for SPA clients
      # @response CSRF token (200) [Hash{ csrf_token: String }]
      # @no_auth
      def show
        token = SecureRandom.base64(32)
        cookie_options = CookieDomainResolver.cookie_options(request.host)
        log_level = Rails.env.production? ? :info : :debug
        AppLogger.log(
          event: "auth.csrf_cookie_set",
          level: log_level,
          host: request.host,
          cookie_domain: cookie_options[:domain],
          same_site: cookie_options[:same_site],
          secure: cookie_options[:secure]
        )
        cookies.signed[:csrf_token] = {
          value: token,
          httponly: false,
          **cookie_options
        }.compact
        if ENV["DEBUG_CSRF_PROBE"] == "1"
          response.set_header("X-CSRF-Probe", "ok")
          response.set_header("X-CSRF-Cookie-Present", cookies.signed[:csrf_token].present?.to_s)
        end
        render json: { csrf_token: token }, status: :ok
      end
    end
  end
end
