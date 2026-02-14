module Account
  class ChangePassword
    def initialize(user:, current_session_token:, current_password:, new_password:)
      @user = user
      @current_session_token = current_session_token
      @current_password = current_password
      @new_password = new_password
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Current password required", code: :validation_error) if @current_password.to_s.blank?
      return ServiceResult.fail("New password required", code: :validation_error) if @new_password.to_s.blank?
      return ServiceResult.fail("Invalid password", code: :invalid_password) unless @user.authenticate(@current_password)

      User.transaction do
        unless @user.update(password: @new_password, password_confirmation: @new_password)
          return ServiceResult.fail(@user.errors.full_messages.to_sentence, code: :invalid_password)
        end

        sessions_revoked = revoke_active_sessions
        AppLogger.log(
          event: "account.password_change.succeeded",
          user_id: @user.id,
          actor_session_token_id: @current_session_token&.id,
          sessions_revoked: sessions_revoked
        )
        ServiceResult.ok(code: :password_updated, data: { sessions_revoked: sessions_revoked })
      end
    rescue StandardError => e
      AppLogger.error(event: "account.password_change.failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to update password", code: :unexpected_error)
    end

    private

    def revoke_active_sessions
      Auth::RevokeUserSessions.new(
        user: @user,
        reason: "password_change",
        actor: @user,
        actor_session_token_id: @current_session_token&.id,
        app_event: "account.session.revoked"
      ).call
    end
  end
end
