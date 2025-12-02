class PasswordMailer < ApplicationMailer
  def reset_instructions(user, raw_token)
    @user = user
    @reset_url = build_reset_url(raw_token)

    mail(
      to: user.email_address,
      subject: "Reset your X-Bid password"
    )
  end

  private

  def build_reset_url(raw_token)
    base = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    "#{base}/reset-password?token=#{raw_token}"
  end
end
