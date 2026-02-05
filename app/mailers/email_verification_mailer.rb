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
    base = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    "#{base}/verify-email?token=#{raw_token}"
  end
end
