require "jwt"

module Auth
  class SessionTokenDecoder
    def self.session_token_from_jwt(token)
      decoded = JWT.decode(
        token,
        Rails.application.secret_key_base,
        true,
        {
          algorithm: "HS256",
          verify_expiration: true,
          verify_iat: true,
          verify_not_before: true,
          required_claims: %w[exp iat nbf]
        }
      ).first
      SessionToken.find(decoded["session_token_id"])
    end
  end
end
