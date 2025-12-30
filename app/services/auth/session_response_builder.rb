module Auth
  class SessionResponseBuilder
    def self.build(user:, session_token:, refresh_token:, jwt_encoder:)
      flags = flags_for(user)
      jwt_payload = {
        user_id: user.id,
        session_token_id: session_token.id,
        is_admin: flags[:is_admin],
        is_superuser: flags[:is_superuser]
      }

      {
        token: jwt_encoder.call(jwt_payload, expires_at: session_token.expires_at),
        refresh_token: refresh_token,
        session_token_id: session_token.id,
        session: session_data(session_token),
        is_admin: flags[:is_admin],
        is_superuser: flags[:is_superuser],
        redirect_path: redirect_path_for(user),
        user: user_data(user, flags: flags)
      }
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

    def self.redirect_path_for(user)
      return "/admin/auctions" if user.superadmin?

      nil
    end

    def self.seconds_remaining_for(session_token)
      [ (session_token.expires_at - Time.current).to_i, 0 ].max
    end
  end
end
