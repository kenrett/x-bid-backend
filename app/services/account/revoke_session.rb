module Account
  class RevokeSession
    def initialize(user:, current_session_token:, session_token_id:)
      @user = user
      @current_session_token = current_session_token
      @session_token_id = session_token_id
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      token = @user.session_tokens.find_by(id: @session_token_id)
      return ServiceResult.fail("Session not found", code: :not_found) unless token

      if @current_session_token.present? && token.id == @current_session_token.id
        return ServiceResult.fail("Cannot revoke the current session via this endpoint", code: :invalid_session)
      end

      token.revoke!
      AppLogger.log(
        event: "account.session.revoked",
        user_id: @user.id,
        revoked_session_token_id: token.id,
        actor_session_token_id: @current_session_token&.id,
        reason: "user_revoked"
      )
      SessionEventBroadcaster.session_invalidated(token, reason: "user_revoked")
      ServiceResult.ok(code: :revoked)
    end
  end
end
