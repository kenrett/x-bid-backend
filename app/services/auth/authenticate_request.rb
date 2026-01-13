module Auth
  class AuthenticateRequest
    Result = Struct.new(:session_token, :method, keyword_init: true)

    def self.call(request)
      session_token = Auth::CookieSessionAuthenticator.session_token_from_request(request)
      return Result.new(session_token: session_token, method: :cookie) if session_token

      return Result.new(session_token: nil, method: nil) unless bearer_allowed?

      Result.new(session_token: Auth::BearerAuthenticator.call(request), method: :bearer)
    end

    def self.bearer_allowed?
      return false if Rails.env.production? && ENV["DISABLE_BEARER_AUTH"].to_s == "true"

      true
    end
  end
end
