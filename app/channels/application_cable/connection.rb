require "jwt"

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_session_token_id

    def connect
      self.current_user, self.current_session_token_id = authenticate_connection
    end

    private

    def authenticate_connection
      token = request.params[:token].presence || authorization_header_token
      reject_unauthorized_connection unless token

      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
      session_token = SessionToken.find_by(id: decoded["session_token_id"])

      reject_unauthorized_connection unless session_token&.active?
      if request.params[:session_token_id].present? && request.params[:session_token_id].to_s != session_token.id.to_s
        reject_unauthorized_connection
      end

      [session_token.user, session_token.id]
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      reject_unauthorized_connection
    end

    def authorization_header_token
      header = request.headers["Authorization"]
      return if header.blank?

      header.split(" ").last
    end
  end
end
