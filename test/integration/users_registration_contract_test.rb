require "test_helper"

class UsersRegistrationContractTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/users returns EXACTLY { token, user } keys" do
    assert_difference("User.count", 1) do
      assert_difference("SessionToken.count", 0) do
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
    assert_equal %w[token user], body.keys.sort
    assert body["token"].present?
    assert body["user"].is_a?(Hash)
  end
end
