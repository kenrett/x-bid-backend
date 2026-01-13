module Auth
  class CookieSessionAuthenticator
    COOKIE_NAME = :bs_session_id

    def self.call(request)
      session_token = session_token_from_request(request)
      return nil unless session_token&.active?

      session_token.user
    end

    def self.session_token_from_request(request)
      cookie_jar = request.cookie_jar
      return nil unless cookie_jar

      session_token_id = cookie_jar.signed[COOKIE_NAME]
      return nil if session_token_id.blank?

      SessionToken.find_by(id: session_token_id)
    end
  end
end
