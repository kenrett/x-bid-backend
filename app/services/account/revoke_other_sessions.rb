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
        SessionEventBroadcaster.session_invalidated(session_token, reason: "revoke_others")
      end

      ServiceResult.ok(code: :revoked, data: { sessions_revoked: revoked })
    end
  end
end
