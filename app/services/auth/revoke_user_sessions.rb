module Auth
  class RevokeUserSessions
    def initialize(
      user:,
      reason:,
      except_session_token_id: nil,
      actor: nil,
      actor_session_token_id: nil,
      request: nil,
      app_event: "auth.session.revoked"
    )
      @user = user
      @reason = reason.to_s
      @except_session_token_id = except_session_token_id
      @actor = actor || user
      @actor_session_token_id = actor_session_token_id
      @request = request
      @app_event = app_event
    end

    def call
      return 0 unless @user

      scope = @user.session_tokens.active
      scope = scope.where.not(id: @except_session_token_id) if @except_session_token_id.present?

      revoked = 0
      scope.find_each do |session_token|
        session_token.revoke!
        revoked += 1
        log_revocation(session_token)
        SessionEventBroadcaster.session_invalidated(session_token, reason: @reason)
      end

      revoked
    end

    private

    def log_revocation(session_token)
      AppLogger.log(
        event: @app_event,
        user_id: @user.id,
        revoked_session_token_id: session_token.id,
        actor_session_token_id: @actor_session_token_id,
        reason: @reason
      )

      AuditLogger.log(
        action: "auth.session.revoked",
        actor: @actor,
        user: @user,
        session_token_id: @actor_session_token_id,
        request: @request,
        payload: {
          revoked_session_token_id: session_token.id,
          actor_session_token_id: @actor_session_token_id,
          reason: @reason
        }.compact
      )
    end
  end
end
