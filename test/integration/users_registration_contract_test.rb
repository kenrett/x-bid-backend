require "test_helper"
require "jwt"

class UsersRegistrationContractTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/users is a legacy alias of /api/v1/signup (session-bound contract)" do
    assert_difference("User.count", 1) do
      assert_difference("SessionToken.count", 1) do
        post "/api/v1/users", params: {
          user: {
            name: "User",
            email_address: "legacy_users_endpoint@example.com",
            password: "password",
            password_confirmation: "password"
          }
        }
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["refresh_token"].present?
    assert body["session_token_id"].present?

    user = User.find_by!(email_address: "legacy_users_endpoint@example.com")
    decoded = JWT.decode(body["access_token"], Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
    assert_equal user.id, decoded.fetch("user_id")
    assert_equal body["session_token_id"], decoded.fetch("session_token_id")
  end
end
