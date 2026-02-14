module Account
  class VerifyEmail
    TOKEN_TTL = 24.hours

    def initialize(raw_token:)
      @raw_token = raw_token
    end

    def call
      return ServiceResult.fail("Token required", code: :invalid_token) if @raw_token.to_s.blank?

      digest = Auth::TokenDigest.digest(@raw_token)
      user = User.lock.find_by(email_verification_token_digest: digest)
      return ServiceResult.fail("Invalid or expired token", code: :invalid_token) unless user

      sent_at = user.email_verification_sent_at
      return ServiceResult.fail("Token has expired", code: :expired_token) if sent_at.blank? || sent_at < TOKEN_TTL.ago

      if user.email_verified_at.present?
        user.update!(email_verification_token_digest: nil, email_verification_sent_at: nil)
        return ServiceResult.ok(code: :already_verified, data: { user: user })
      end

      User.transaction do
        apply_pending_email!(user)
        user.update!(
          email_verified_at: Time.current,
          email_verification_token_digest: nil,
          email_verification_sent_at: nil
        )
      end

      sessions_revoked = Auth::RevokeUserSessions.new(
        user: user,
        reason: "email_change",
        actor: user
      ).call
      AppLogger.log(event: "account.email_verification.verified", user_id: user.id, sessions_revoked: sessions_revoked)
      ServiceResult.ok(code: :verified, data: { user: user })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :invalid_email, record: e.record)
    rescue StandardError => e
      AppLogger.error(event: "account.email_verification.verify_failed", error: e)
      ServiceResult.fail("Unable to verify email", code: :unexpected_error)
    end

    private

    def apply_pending_email!(user)
      pending = user.unverified_email_address.to_s.strip
      return if pending.blank?

      user.update!(email_address: pending, unverified_email_address: nil)
    end
  end
end
