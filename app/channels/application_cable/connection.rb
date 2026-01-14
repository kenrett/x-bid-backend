module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token

    def connect
      set_storefront_context!
      log_connection_diagnostics
      session_token = authenticate_connection
      self.current_session_token = session_token
      self.current_user = session_token.user
      AppLogger.log(
        event: "action_cable.connect.accepted",
        **connection_log_context,
        user_id: current_user.id,
        session_token_id: current_session_token.id
      )
    end

    private

    def authenticate_connection
      session_token_id = cookies.signed[:bs_session_id]
      session_token = SessionToken.find_by(id: session_token_id)

      unless session_token
        reason = session_token_id.present? ? :unknown_session : :missing_session_cookie
        log_rejected_connection(reason)
        reject_unauthorized_connection
      end

      unless session_token.active?
        log_rejected_connection(:unknown_session)
        reject_unauthorized_connection
      end

      session_token
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
      AppLogger.log(
        event: "action_cable.connect.rejected",
        level: :warn,
        reason: reason.to_s,
        **connection_log_context,
        token_present: false
      )
    end

    def log_connection_diagnostics
      env_keys = request.env.keys.grep(/\AHTTP_|^action_dispatch\.|^rack\.|^REQUEST_|^REMOTE_|^SERVER_/).sort
      AppLogger.log(
        event: "action_cable.connect.diagnostics",
        **connection_log_context,
        env_keys: env_keys,
        param_keys: request.params.keys.sort,
        token_present: false
      )
    end

    def connection_log_context
      {
        request_id: request.request_id,
        controller_action: "#{self.class.name}#connect",
        controller: self.class.name,
        action: "connect",
        method: request.request_method,
        path: request.path,
        origin: request.headers["Origin"],
        host: request.host,
        cookie_present: request.headers["Cookie"].present?,
        authorization_present: request.headers["Authorization"].present?,
        cable_session_cookie_present: cookies.encrypted[:cable_session].present?,
        browser_session_cookie_present: cookies.signed[:bs_session_id].present?,
        storefront_key: Current.storefront_key,
        storefront_key_param_present: storefront_key_param_present?
      }
    end

    def storefront_key_param_present?
      request.params[:storefront].present? ||
        request.params[:storefront_key].present? ||
        request.params[:x_storefront].present?
    end
  end
end
