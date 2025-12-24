module Auth
  class PasswordReset
    MINIMUM_RESPONSE_DURATION = 0.35.seconds

    def initialize(user:, reset_params:, environment:, request: nil)
      @user = user
      @reset_params = reset_params
      @environment = environment
      @request = request
    end

    def request_reset
      start_time = monotonic_time
      result = perform_request_reset

      result
    ensure
      ensure_minimum_duration(start_time)
    end

    def reset_password
      PasswordResetToken.transaction do
        token = PasswordResetToken.find_valid_by_raw_token(@reset_params[:token], lock: true)
        return ServiceResult.fail("Invalid or expired token") unless token

        user = token.user
        return ServiceResult.fail("User account disabled") if user.disabled?

        if user.update(password: @reset_params[:password], password_confirmation: @reset_params[:password_confirmation])
          token.mark_used!
          revoke_active_sessions(user)
          ServiceResult.ok(message: "Password updated")
        else
          ServiceResult.fail(user.errors.full_messages.to_sentence)
        end
      end
    end

    private

    def perform_request_reset
      return ServiceResult.ok(message: "ok") unless @user&.active?

      token, raw_token = PasswordResetToken.generate_for(user: @user)
      deliver_email(raw_token)
      AppLogger.log(event: "auth.password_reset.requested", user_id: @user.id)

      debug_token = @environment.production? ? nil : raw_token
      ServiceResult.ok(message: "ok", debug_token: debug_token)
    rescue StandardError => e
      AppLogger.error(event: "auth.password_reset.request_failed", error: e, user_id: @user&.id)
      ServiceResult.ok(message: "ok")
    end

    def deliver_email(raw_token)
      PasswordMailer.reset_instructions(@user, raw_token).deliver_later
    rescue StandardError => e
      AppLogger.error(event: "auth.password_reset.mail_failure", error: e, user_id: @user.id)
    end

    def revoke_active_sessions(user)
      user.session_tokens.active.find_each do |session_token|
        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "password_reset")
      end
    end

    def ensure_minimum_duration(start_time)
      return unless start_time

      elapsed = monotonic_time - start_time
      sleep_duration = MINIMUM_RESPONSE_DURATION - elapsed
      sleep(sleep_duration) if sleep_duration.positive?
    rescue StandardError => e
      AppLogger.error(event: "auth.password_reset.uniform_timing_failed", error: e)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
