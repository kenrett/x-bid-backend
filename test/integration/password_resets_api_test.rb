require "test_helper"

class PasswordResetsApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name: "User",
      email_address: "user@example.com",
      password: "password123",
      password_confirmation: "password123",
      bid_credits: 0
    )
  end

  test "returns accepted and includes debug token in test env" do
    post "/api/v1/password/forgot", params: { password: { email_address: @user.email_address } }

    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert body["debug_token"].present?
  end

  test "creates reset token and allows password reset" do
    post "/api/v1/password/forgot", params: { password: { email_address: @user.email_address } }
    token = JSON.parse(response.body)["debug_token"]

    post "/api/v1/password/reset", params: { password: { token: token, password: "newpassword123", password_confirmation: "newpassword123" } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Password updated", body["message"]
    assert @user.reload.authenticate("newpassword123")
    assert_equal 0, @user.session_tokens.active.count
  end

  test "rejects invalid token" do
    post "/api/v1/password/reset", params: { password: { token: "invalid", password: "newpass123", password_confirmation: "newpass123" } }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "Invalid or expired token", body["error"]
  end

  test "rejects disabled user reset" do
    @user.update!(status: :disabled)
    post "/api/v1/password/forgot", params: { password: { email_address: @user.email_address } }
    token = JSON.parse(response.body)["debug_token"]

    post "/api/v1/password/reset", params: { password: { token: token, password: "newpassword123", password_confirmation: "newpassword123" } }

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "User account disabled", body["error"]
  end
end
