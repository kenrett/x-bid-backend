module Auth
  class CookieSessionAuthenticator
    COOKIE_NAME = :"__Host-bs_session_id"
    LEGACY_COOKIE_NAME = :bs_session_id
    COOKIE_NAMES = [ COOKIE_NAME, LEGACY_COOKIE_NAME ].freeze

    def self.call(request)
      session_token = session_token_from_request(request)
      return nil unless session_token&.active?

      session_token.user
    end

    def self.session_token_from_request(request)
      cookie_jar = request.cookie_jar
      return nil unless cookie_jar

      session_token_id = session_cookie_id_from_jar(cookie_jar)
      return nil if session_token_id.blank?

      SessionToken.find_by(id: session_token_id)
    end

    def self.session_cookie_id_from_jar(cookie_jar)
      COOKIE_NAMES.each do |cookie_name|
        value = cookie_jar.signed[cookie_name]
        return value if value.present?
      end

      nil
    end
  end
end
