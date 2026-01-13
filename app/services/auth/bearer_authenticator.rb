require "jwt"

module Auth
  class BearerAuthenticator
    def self.call(request)
      token = bearer_token_from_request(request)
      return nil if token.blank?

      Auth::SessionTokenDecoder.session_token_from_jwt(token)
    end

    def self.bearer_token_from_request(request)
      header = request.headers["Authorization"].to_s
      return nil if header.blank?

      header.split(" ").last
    end
  end
end
