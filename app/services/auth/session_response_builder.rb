module Auth
  class SessionResponseBuilder
    def self.build(user:, session_token:, refresh_token:, jwt_encoder:)
      flags = flags_for(user)
      payload = {
        session_token_id: session_token.id,
        user: user_data(user, flags: flags)
      }
      return payload unless Auth::AuthenticateRequest.bearer_allowed?

      jwt_payload = {
        user_id: user.id,
        session_token_id: session_token.id,
        is_admin: flags[:is_admin],
        is_superuser: flags[:is_superuser]
      }

      payload.merge(
        access_token: jwt_encoder.call(jwt_payload, expires_at: session_token.expires_at),
        refresh_token: refresh_token
      )
    end

    def self.flags_for(user)
      {
        is_admin: user.admin? || user.superadmin?,
        is_superuser: user.superadmin?
      }
    end

    def self.user_data(user, flags: flags_for(user))
      UserSerializer.new(user).as_json.merge(flags)
    end

    def self.session_data(session_token)
      {
        session_token_id: session_token.id,
        session_expires_at: session_token.expires_at.iso8601,
        seconds_remaining: seconds_remaining_for(session_token)
      }
    end

    def self.remaining_data(user:, session_token:)
      flags = flags_for(user)
      {
        session_token_id: session_token.id,
        session_expires_at: session_token.expires_at.iso8601,
        remaining_seconds: remaining_seconds_for(session_token),
        user: user_data(user, flags: flags),
        is_admin: flags[:is_admin],
        is_superuser: flags[:is_superuser]
      }
    end

    def self.redirect_path_for(user)
      return "/admin/auctions" if user.superadmin?

      nil
    end

    def self.remaining_seconds_for(session_token)
      [ (session_token.expires_at - Time.current).to_i, 0 ].max
    end

    def self.seconds_remaining_for(session_token)
      remaining_seconds_for(session_token)
    end
  end
end
