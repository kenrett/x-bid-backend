module Account
  class RevokeOtherSessions
    def initialize(user:, current_session_token:)
      @user = user
      @current_session_token = current_session_token
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Current session required", code: :invalid_session) unless @current_session_token

      revoked = 0
      @user.session_tokens.active.where.not(id: @current_session_token.id).find_each do |session_token|
        session_token.revoke!
        revoked += 1
        AppLogger.log(
          event: "account.session.revoked",
          user_id: @user.id,
          revoked_session_token_id: session_token.id,
          actor_session_token_id: @current_session_token.id,
          reason: "revoke_others"
        )
        AuditLogger.log(
          action: "auth.session.revoked",
          actor: @user,
          user: @user,
          session_token_id: @current_session_token.id,
          payload: {
            revoked_session_token_id: session_token.id,
            actor_session_token_id: @current_session_token.id,
            reason: "revoke_others"
          }
        )
        SessionEventBroadcaster.session_invalidated(session_token, reason: "revoke_others")
      end

      AppLogger.log(
        event: "account.sessions.revoked_others",
        user_id: @user.id,
        actor_session_token_id: @current_session_token.id,
        sessions_revoked: revoked
      )
      ServiceResult.ok(code: :revoked, data: { sessions_revoked: revoked })
    end
  end
end
