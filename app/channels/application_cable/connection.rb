require "jwt"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token_id

    def connect
      self.current_user, self.current_session_token_id = authenticate_connection
    end

    private

    def authenticate_connection
      token = websocket_token
      unless token
        Rails.logger.warn("ActionCable connection rejected: no token provided via Authorization header, token query param, or secure cookie")
        reject_unauthorized_connection
      end

      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
      session_token = SessionToken.find_by(id: decoded["session_token_id"])

      reject_unauthorized_connection unless session_token&.active?
      if request.params[:session_token_id].present? && request.params[:session_token_id].to_s != session_token.id.to_s
        reject_unauthorized_connection
      end

      [ session_token.user, session_token.id ]
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      reject_unauthorized_connection
    end

    def websocket_token
      # Browsers cannot set custom WebSocket headers, so support query param auth.
      # Prefer Authorization header when present; otherwise accept `?token=...` or a secure encrypted cookie.
      authorization_header_token || request.params[:token].presence || cookies.encrypted[:jwt]
    end

    def authorization_header_token
      header = request.headers["Authorization"]
      return if header.blank?

      header.split(" ").last
    end
  end
end
