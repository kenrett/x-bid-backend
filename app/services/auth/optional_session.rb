require "jwt"

module Auth
  class OptionalSession
    def self.session_token_from_request(request)
      token = bearer_token_from_request(request)
      return nil if token.blank?

      decoded = JWT.decode(
        token,
        Rails.application.secret_key_base,
        true,
        {
          algorithm: "HS256",
          verify_expiration: true,
          verify_iat: true,
          verify_not_before: true
        }
      ).first

      session_token = SessionToken.find_by(id: decoded["session_token_id"])
      return nil unless session_token&.active?

      session_token
    rescue JWT::DecodeError, JWT::ExpiredSignature
      nil
    end

    def self.bearer_token_from_request(request)
      header = request.headers["Authorization"].to_s
      return nil if header.blank?

      header.split(" ").last
    end
  end
end
