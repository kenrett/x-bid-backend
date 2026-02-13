require "jwt"

module Auth
  class OptionalSession
    Result = Struct.new(:session_token, :user, keyword_init: true)

    def self.call(request)
      session_token = session_token_from_request(request)
      Result.new(session_token: session_token, user: session_token&.user)
    end

    def self.session_token_from_request(request)
      cookie_session_token = cookie_session_token_from_request(request)
      return cookie_session_token if cookie_session_token

      token = bearer_token_from_request(request)
      return nil if token.blank?

      session_token = Auth::SessionTokenDecoder.session_token_from_jwt(token)
      return nil unless session_token&.active?

      session_token
    rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::MissingRequiredClaim, ActiveRecord::RecordNotFound
      nil
    end

    def self.cookie_session_token_from_request(request)
      session_token = Auth::CookieSessionAuthenticator.session_token_from_request(request)
      return nil unless session_token&.active?

      session_token
    end

    def self.bearer_token_from_request(request)
      header = request.headers["Authorization"].to_s
      return nil if header.blank?

      header.split(" ").last
    end
  end
end
