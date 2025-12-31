require "securerandom"

module Account
  class RequestEmailChange
    TOKEN_TTL = 24.hours
    RESEND_COOLDOWN = 60.seconds

    def initialize(user:, new_email_address:, current_password:, environment:)
      @user = user
      @new_email_address = new_email_address
      @current_password = current_password
      @environment = environment
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Current password required", code: :validation_error) if @current_password.to_s.blank?
      return ServiceResult.fail("Invalid password", code: :invalid_password) unless @user.authenticate(@current_password)

      normalized_email = normalize_email(@new_email_address)
      return ServiceResult.fail("New email address required", code: :validation_error) if normalized_email.blank?
      return ServiceResult.fail("New email address is invalid", code: :invalid_email) unless normalized_email.match?(/\A[^@\s]+@[^@\s]+\z/)
      return ServiceResult.fail("New email address matches current email", code: :invalid_email) if normalized_email == @user.email_address
      return ServiceResult.fail("Email address has already been taken", code: :invalid_email) if User.exists?(email_address: normalized_email)

      return ServiceResult.fail("Please wait before requesting another verification email", code: :rate_limited) if resend_limited?

      raw_token = SecureRandom.hex(32)
      digest = Auth::TokenDigest.digest(raw_token)

      @user.update!(
        unverified_email_address: normalized_email,
        email_verified_at: nil,
        email_verification_token_digest: digest,
        email_verification_sent_at: Time.current
      )

      deliver_email(to: normalized_email, raw_token: raw_token)
      AppLogger.log(event: "account.email_change.requested", user_id: @user.id)

      ServiceResult.ok(code: :verification_sent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :validation_error, record: e.record)
    rescue StandardError => e
      AppLogger.error(event: "account.email_change.failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to request email change", code: :unexpected_error)
    end

    private

    def normalize_email(email)
      email.to_s.strip.downcase
    end

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
