require "jwt"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token

    def connect
      session_token = authenticate_connection
      self.current_session_token = session_token
      self.current_user = session_token.user
      Rails.logger.info(
        "ActionCable connection accepted: user_id=#{current_user.id} session_token_id=#{current_session_token.id} host=#{request.host} origin=#{request.headers['Origin']}"
      )
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
      cookie_present = request.headers["Cookie"].present?
      origin = request.headers["Origin"]
      storefront_key = Current.storefront_key if defined?(Current)

      details = [
        "reason=#{reason}",
        "host=#{request.host}",
        "path=#{request.path}",
        "origin=#{origin.presence || 'none'}",
        "cookie_present=#{cookie_present}",
        "storefront_key=#{storefront_key.presence || 'unknown'}"
      ]
      details << "session_token_id=#{session_token_id}" if session_token_id.present?
      Rails.logger.warn("ActionCable connection rejected: #{details.join(' ')}")
    end
  end
end
