require "test_helper"
require "jwt"

class SignupApiTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/signup (nested payload) creates user and returns login-equivalent session contract" do
    assert_difference("User.count", 1) do
      assert_difference("SessionToken.count", 1) do
        post "/api/v1/signup", params: {
          user: {
            name: "User",
            email_address: "signup_contract@example.com",
            password: "password",
            password_confirmation: "password"
          }
        }
      end
    end

    assert_response :created
    body = JSON.parse(response.body)

    assert body["token"].present?
    assert body["refresh_token"].present?
    assert body["session"].is_a?(Hash)
    assert_equal body["session"]["session_token_id"], body["session_token_id"]
    assert body["session"]["session_expires_at"].present?
    assert body["session"]["seconds_remaining"].is_a?(Integer)

    assert_equal false, body["is_admin"]
    assert_equal false, body["is_superuser"]

    user = User.find_by!(email_address: "signup_contract@example.com")
    assert_equal user.id, body.dig("user", "id")

    decoded = JWT.decode(body["token"], Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
    assert_equal user.id, decoded.fetch("user_id")
    assert_equal body["session_token_id"], decoded.fetch("session_token_id")

    # Refresh token is the raw token for a SessionToken; ensure it resolves to an active session.
    session_token = SessionToken.find_active_by_raw_token(body["refresh_token"])
    assert session_token.present?
    assert_equal user.id, session_token.user_id
    assert_equal body["session_token_id"], session_token.id
  end

  test "POST /api/v1/signup (flat payload) creates user and returns login-equivalent session contract" do
    assert_difference("User.count", 1) do
      assert_difference("SessionToken.count", 1) do
        post "/api/v1/signup", params: {
          name: "User",
          email_address: "signup_contract_flat@example.com",
          password: "password",
          password_confirmation: "password"
        }
      end
    end

    assert_response :created
    body = JSON.parse(response.body)

    assert body["token"].present?
    assert body["refresh_token"].present?
    assert body["session"].is_a?(Hash)
    assert body["session_token_id"].present?

    user = User.find_by!(email_address: "signup_contract_flat@example.com")
    decoded = JWT.decode(body["token"], Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
    assert_equal user.id, decoded.fetch("user_id")
    assert_equal body["session_token_id"], decoded.fetch("session_token_id")
  end

  test "POST /api/v1/signup returns 422 with errors on invalid payload" do
    post "/api/v1/signup", params: { user: { email_address: "bad@example.com" } }

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert body["errors"].is_a?(Array)
  end
end
