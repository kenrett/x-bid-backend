require "securerandom"

module Account
  class ResendEmailVerification
    RESEND_COOLDOWN = 60.seconds

    def initialize(user:, environment:)
      @user = user
      @environment = environment
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Email already verified", code: :already_verified) if @user.email_verified? && @user.unverified_email_address.blank?
      return ServiceResult.fail("Please wait before requesting another verification email", code: :rate_limited) if resend_limited?

      target_email = @user.unverified_email_address.presence || @user.email_address
      raw_token = SecureRandom.hex(32)
      digest = Auth::TokenDigest.digest(raw_token)

      @user.update!(
        email_verification_token_digest: digest,
        email_verification_sent_at: Time.current
      )

      deliver_email(to: target_email, raw_token: raw_token)
      AppLogger.log(event: "account.email_verification.resent", user_id: @user.id)

      ServiceResult.ok(code: :verification_sent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :validation_error, record: e.record)
    rescue StandardError => e
      AppLogger.error(event: "account.email_verification.resend_failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to resend verification email", code: :unexpected_error)
    end

    private

    def resend_limited?
      sent_at = @user.email_verification_sent_at
      sent_at.present? && sent_at > RESEND_COOLDOWN.ago
    end

    def deliver_email(to:, raw_token:)
      EmailVerificationMailer.verify_email(@user, to, raw_token).deliver_later
      return if @environment.production?

      AppLogger.log(event: "account.email_verification.debug_token_issued", user_id: @user.id, debug_token: raw_token)
    rescue StandardError => e
      AppLogger.error(event: "account.email_verification.mail_failure", error: e, user_id: @user.id)
    end
  end
end
