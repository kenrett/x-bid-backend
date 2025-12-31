class EmailVerificationMailer < ApplicationMailer
  def verify_email(user, to_email_address, raw_token)
    @user = user
    @verification_url = build_verification_url(raw_token)

    mail(
      to: to_email_address,
      subject: "Verify your X-Bid email address"
    )
  end

  private

  def build_verification_url(raw_token)
    base = ENV.fetch("APP_URL", "http://localhost:3000")
    "#{base}/api/v1/email_verifications/verify?token=#{raw_token}"
  end
end
