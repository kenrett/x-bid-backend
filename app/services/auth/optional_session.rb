require "jwt"

module Auth
  class OptionalSession
    def self.session_token_from_request(request)
      token = bearer_token_from_request(request)
      return nil if token.blank?

      session_token = Auth::SessionTokenDecoder.session_token_from_jwt(token)
      return nil unless session_token&.active?

      session_token
    rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
      nil
    end

    def self.bearer_token_from_request(request)
      header = request.headers["Authorization"].to_s
      return nil if header.blank?

      header.split(" ").last
    end
  end
end
