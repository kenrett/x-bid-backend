module Api
  module V1
    class AuthDebugController < ApplicationController
      before_action :ensure_auth_debug_enabled

      # GET /api/v1/auth/debug
      # @summary Report auth header/cookie presence for the current request
      def show
        origin = request.headers["Origin"]
        render json: {
          host: request.host,
          origin: origin,
          storefront_key: Current.storefront_key,
          cookie_header_present: request.headers["Cookie"].present?,
          browser_session_cookie_present: cookies.signed[:bs_session_id].present?,
          authorization_header_present: request.headers["Authorization"].present?
        }
      end

      private

      def ensure_auth_debug_enabled
        return if auth_debug_enabled?
        return if performed?

        render json: { error: "Not found" }, status: :not_found
      end

      def auth_debug_enabled?
        ENV["AUTH_DEBUG_ENABLED"].to_s.strip.casecmp("true").zero?
      end
    end
  end
end
