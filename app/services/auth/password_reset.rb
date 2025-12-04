module Auth
  class PasswordReset
    Result = Struct.new(:error, :message, :debug_token, keyword_init: true)

    def initialize(user:, reset_params:, environment:, request: nil)
      @user = user
      @reset_params = reset_params
      @environment = environment
      @request = request
    end

    def request_reset
      return Result.new(message: "ok") unless @user&.active?

      token, raw_token = PasswordResetToken.generate_for(user: @user)
      deliver_email(raw_token)

      debug_token = @environment.production? ? nil : raw_token
      Result.new(message: "ok", debug_token: debug_token)
    rescue StandardError => e
      Rails.logger.warn("Failed to process password reset request: #{e.message}")
      Result.new(message: "ok")
    end

    def reset_password
      token = PasswordResetToken.find_valid_by_raw_token(@reset_params[:token])
      return Result.new(error: "Invalid or expired token") unless token

      user = token.user
      return Result.new(error: "User account disabled") if user.disabled?

      if user.update(password: @reset_params[:password], password_confirmation: @reset_params[:password_confirmation])
        token.mark_used!
        revoke_active_sessions(user)
        Result.new(message: "Password updated")
      else
        Result.new(error: user.errors.full_messages.to_sentence)
      end
    end

    private

    def deliver_email(raw_token)
      PasswordMailer.reset_instructions(@user, raw_token).deliver_later
    rescue StandardError => e
      Rails.logger.warn("Failed to enqueue password reset email: #{e.message}")
    end

    def revoke_active_sessions(user)
      user.session_tokens.active.find_each do |session_token|
        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "password_reset")
      end
    end
  end
end
