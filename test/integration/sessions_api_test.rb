require "test_helper"

class SessionsApiTest < ActionDispatch::IntegrationTest
  def setup
    @superadmin = User.create!(
      name: "Super",
      email_address: "super@example.com",
      password: "password",
      role: :superadmin,
      bid_credits: 0
    )
  end

  test "login response includes is_admin and is_superuser flags" do
    post "/api/v1/login", params: {
      session: {
        email_address: @superadmin.email_address,
        password: "password"
      }
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["user"]["is_admin"]
    assert_equal true, body["user"]["is_superuser"]
  end

  test "refresh response includes is_admin and is_superuser flags" do
    session_token, refresh_token = SessionToken.generate_for(user: @superadmin)

    post "/api/v1/session/refresh", params: { session: { refresh_token: refresh_token } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["user"]["is_admin"]
    assert_equal true, body["user"]["is_superuser"]
  ensure
    session_token&.destroy
  end
end
