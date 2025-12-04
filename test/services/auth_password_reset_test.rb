require "test_helper"

class AuthPasswordResetTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    Rails.cache.clear
  end

  test "request_reset returns debug token in test env" do
    result = Auth::PasswordReset.new(user: @user, reset_params: {}, environment: Rails.env).request_reset

    assert_equal "ok", result.message
    assert result.debug_token.present?
  end

  test "reset_password updates password with valid token" do
    token, raw_token = PasswordResetToken.generate_for(user: @user)

    result = Auth::PasswordReset.new(
      user: nil,
      reset_params: { token: raw_token, password: "newpass123", password_confirmation: "newpass123" },
      environment: Rails.env
    ).reset_password

    assert_nil result.error
    assert_equal "Password updated", result.message
    assert @user.reload.authenticate("newpass123")
  end

  test "reset_password rejects disabled user" do
    @user.update!(status: :disabled)
    _token, raw_token = PasswordResetToken.generate_for(user: @user)

    result = Auth::PasswordReset.new(
      user: nil,
      reset_params: { token: raw_token, password: "newpass123", password_confirmation: "newpass123" },
      environment: Rails.env
    ).reset_password

    assert_equal "User account disabled", result.error
  end

  test "reset_password rejects invalid token" do
    result = Auth::PasswordReset.new(
      user: nil,
      reset_params: { token: "invalid", password: "newpass123", password_confirmation: "newpass123" },
      environment: Rails.env
    ).reset_password

    assert_equal "Invalid or expired token", result.error
  end
end
