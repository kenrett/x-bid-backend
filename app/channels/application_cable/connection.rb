require "jwt"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token

    def connect
      session_token = authenticate_connection
      self.current_session_token = session_token
      self.current_user = session_token.user
    end

    private

    def authenticate_connection
      session_token = session_token_from_cable_cookie || session_token_from_authorization_header
      unless session_token&.active?
        log_rejected_connection(session_token ? "inactive_session" : "missing_cookie")
        reject_unauthorized_connection
      end

      session_token
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      log_rejected_connection("invalid_token")
      reject_unauthorized_connection
    end

    def session_token_from_cable_cookie
      session_token_id = cookies.signed[:cable_session]
      return if session_token_id.blank?

      SessionToken.find_by(id: session_token_id)
    end

    def session_token_from_authorization_header
      token = authorization_header_token
      return if token.blank?

      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
      SessionToken.find_by(id: decoded["session_token_id"])
    end

    def authorization_header_token
      header = request.headers["Authorization"]
      return if header.blank?

      header.split(" ").last
    end

    def log_rejected_connection(reason)
      session_token_id = cookies.signed[:cable_session]
      if session_token_id.present?
        Rails.logger.warn("ActionCable connection rejected: reason=#{reason} session_token_id=#{session_token_id}")
      else
        Rails.logger.warn("ActionCable connection rejected: reason=#{reason}")
      end
    end
  end
end
