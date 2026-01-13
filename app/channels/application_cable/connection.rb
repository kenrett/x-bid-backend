require "jwt"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token

    def connect
      log_connection_diagnostics
      set_storefront_context!
      session_token = authenticate_connection
      self.current_session_token = session_token
      self.current_user = session_token.user
      Rails.logger.info(
        "ActionCable connection accepted: user_id=#{current_user.id} session_token_id=#{current_session_token.id} host=#{request.host} origin=#{request.headers['Origin']} storefront_key=#{Current.storefront_key}"
      )
    end

    private

    def authenticate_connection
      token = websocket_token
      session_token =
        if token.present?
          Auth::SessionTokenDecoder.session_token_from_jwt(token)
        else
          session_token_from_cable_cookie
        end

      unless session_token
        if token.present?
          reason = "invalid_token"
        elsif cookies.signed[:cable_session].present?
          reason = "invalid_cookie"
        else
          reason = "missing_token"
        end
        log_rejected_connection(reason)
        reject_unauthorized_connection
      end

      unless session_token.active?
        log_rejected_connection("inactive_session")
        reject_unauthorized_connection
      end

      session_token
    rescue JWT::ExpiredSignature
      log_rejected_connection("expired_token")
      reject_unauthorized_connection
    rescue JWT::DecodeError, JWT::VerificationError, ActiveRecord::RecordNotFound
      log_rejected_connection("invalid_token")
      reject_unauthorized_connection
    end

    def session_token_from_cable_cookie
      session_token_id = cookies.signed[:cable_session]
      return if session_token_id.blank?

      SessionToken.find_by(id: session_token_id)
    end

    def websocket_token
      query_param_token || query_param_authorization || subprotocol_token
    end

    def query_param_token
      request.params[:token].presence
    end

    def query_param_authorization
      raw = request.params[:authorization].presence || request.params[:auth].presence
      return if raw.blank?

      raw.to_s.split(" ").last
    end

    def subprotocol_token
      raw = request.headers["Sec-WebSocket-Protocol"].to_s
      return if raw.blank?

      protocols = raw.split(",").map(&:strip).reject(&:blank?)
      protocols.each do |protocol|
        return protocol.delete_prefix("jwt.") if protocol.start_with?("jwt.")
        return protocol.delete_prefix("bearer.") if protocol.start_with?("bearer.")
        return protocol.delete_prefix("token=") if protocol.start_with?("token=")
      end

      jwt_like = protocols.find { |protocol| protocol.count(".") == 2 }
      jwt_like
    end

    def set_storefront_context!
      key = request.params[:storefront].presence ||
        request.params[:storefront_key].presence ||
        request.params[:x_storefront].presence

      if key.blank?
        key = Storefront::Resolver.resolve(request) if defined?(Storefront::Resolver)
      end

      Current.storefront_key = key.to_s.presence || Current.storefront_key
      if defined?(ErrorReporting::StorefrontTagging)
        ErrorReporting::StorefrontTagging.set!(storefront_key: Current.storefront_key || "unknown")
      end
    end

    def log_rejected_connection(reason)
      cookie_present = request.headers["Cookie"].present?
      cookie_names = RequestDiagnostics.cookie_names_from_header(request.headers["Cookie"])
      origin = request.headers["Origin"]
      storefront_key = Current.storefront_key if defined?(Current)

      details = [
        "reason=#{reason}",
        "host=#{request.host}",
        "path=#{request.path}",
        "origin=#{origin.presence || 'none'}",
        "cookie_present=#{cookie_present}",
        "cookie_names=#{cookie_names.join(',')}",
        "storefront_key=#{storefront_key.presence || 'unknown'}"
      ]
      Rails.logger.warn("ActionCable connection rejected: #{details.join(' ')}")
    end

    def log_connection_diagnostics
      env_keys = request.env.keys.grep(/\AHTTP_|^action_dispatch\.|^rack\.|^REQUEST_|^REMOTE_|^SERVER_/).sort
      cookie_header = request.headers["Cookie"]
      auth_token = websocket_token
      AppLogger.log(
        event: "action_cable.connect.diagnostics",
        request_id: request.request_id,
        path: request.path,
        origin: request.headers["Origin"],
        host: request.host,
        env_keys: env_keys,
        cookie_present: cookie_header.present?,
        cookie_names: RequestDiagnostics.cookie_names_from_header(cookie_header),
        param_keys: request.params.keys.sort,
        token_present: auth_token.present?,
        token_redacted: RequestDiagnostics.redact_token(auth_token)
      )
    end
  end
end
