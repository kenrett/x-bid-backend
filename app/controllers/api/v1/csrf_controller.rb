module Api
  module V1
    class CsrfController < ApplicationController
      # GET /api/v1/csrf
      # @summary Returns CSRF token for SPA clients
      # @response CSRF token (200) [Hash{ csrf_token: String }]
      # @no_auth
      def show
        token = SecureRandom.base64(32)
        cookies.signed[:csrf_token] = {
          value: token,
          httponly: false,
          secure: Rails.env.production?,
          same_site: :lax,
          domain: CookieDomainResolver.domain_for(request.host),
          path: "/"
        }.compact
        render json: { csrf_token: token }, status: :ok
      end
    end
  end
end
