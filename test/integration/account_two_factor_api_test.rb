require "test_helper"
require "jwt"
require "rotp"

class AccountTwoFactorApiTest < ActionDispatch::IntegrationTest
  test "enable 2FA and require OTP for login" do
    user = User.create!(name: "User", email_address: "two_factor@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("two_factor"), expires_at: 1.hour.from_now)

    post "/api/v1/account/2fa/setup", headers: auth_headers(user, session_token)
    assert_response :success
    setup_body = JSON.parse(response.body)
    secret = setup_body.fetch("secret")

    totp = ROTP::TOTP.new(secret, issuer: "X-Bid")
    post "/api/v1/account/2fa/verify", params: { code: totp.now }, headers: auth_headers(user, session_token)
    assert_response :success
    verify_body = JSON.parse(response.body)
    recovery_codes = verify_body.fetch("recovery_codes")
    assert recovery_codes.any?

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password" } }
    assert_response :unauthorized
    assert_equal "two_factor_required", JSON.parse(response.body).dig("error", "code").to_s

    post "/api/v1/login", params: { session: { email_address: user.email_address, password: "password", otp: totp.now } }
    assert_response :success
  end

  test "recovery code works once" do
    user = User.create!(name: "User", email_address: "two_factor_recovery@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("two_factor_recovery"), expires_at: 1.hour.from_now)

    post "/api/v1/account/2fa/setup", headers: auth_headers(user, session_token)
    assert_response :success
    secret = JSON.parse(response.body).fetch("secret")

    totp = ROTP::TOTP.new(secret, issuer: "X-Bid")
    post "/api/v1/account/2fa/verify", params: { code: totp.now }, headers: auth_headers(user, session_token)
    assert_response :success
    recovery_code = JSON.parse(response.body).fetch("recovery_codes").first

    get "/api/v1/csrf"
    csrf_token = JSON.parse(response.body).fetch("csrf_token")
    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "password", recovery_code: recovery_code } },
         headers: { "X-CSRF-Token" => csrf_token }
    assert_response :success

    get "/api/v1/csrf"
    csrf_token = JSON.parse(response.body).fetch("csrf_token")
    post "/api/v1/login",
         params: { session: { email_address: user.email_address, password: "password", recovery_code: recovery_code } },
         headers: { "X-CSRF-Token" => csrf_token }
    assert_response :unauthorized
    assert_equal "invalid_two_factor_code", JSON.parse(response.body).dig("error", "code").to_s
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
