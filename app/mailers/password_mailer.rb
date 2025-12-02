class PasswordMailer < ApplicationMailer
  def reset_instructions(user, raw_token)
    @user = user
    @reset_url = build_reset_url(raw_token)

    mail(
      to: user.email_address,
      subject: "Reset your X-Bid password",
      body: <<~BODY
        Hello #{user.name.presence || "there"},

        A password reset was requested for your X-Bid account. If this was you, reset your password here:
        #{@reset_url}

        If you did not request this, you can ignore this email.
      BODY
    )
  end

  private

  def build_reset_url(raw_token)
    base = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    "#{base}/reset-password?token=#{raw_token}"
  end
end
