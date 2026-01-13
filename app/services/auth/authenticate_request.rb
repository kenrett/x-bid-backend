module Auth
  class AuthenticateRequest
    def self.call(request)
      session_token = Auth::CookieSessionAuthenticator.session_token_from_request(request)
      return session_token if session_token

      Auth::BearerAuthenticator.call(request)
    end
  end
end
