module Api
  module V1
    class DiagnosticsController < ApplicationController
      before_action :ensure_diagnostics_enabled

      # @summary Report auth-related diagnostics for the current request
      def auth
        origin = request.headers["Origin"]
        render json: {
          host: request.host,
          origin: origin,
          origin_allowed: origin.present? ? FrontendOrigins.allowed_origin?(origin) : false,
          cookie_domain: CookieDomainResolver.domain_for(request.host),
          browser_session_cookie_present: cookies.signed[:bs_session_id].present?
        }
      end

      private

      def ensure_diagnostics_enabled
        return if diagnostics_enabled?

        render json: { error: "Not found" }, status: :not_found
      end

      def diagnostics_enabled?
        return true unless Rails.env.production?

        ENV["DIAGNOSTICS_ENABLED"].to_s.strip.casecmp("true").zero?
      end
    end
  end
end
