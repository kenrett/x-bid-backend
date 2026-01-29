require "test_helper"

class LoggedInTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Logged In User",
      email_address: "logged-in@example.com",
      password: "password",
      bid_credits: 0
    )
  end

  test "logged_in returns true with session cookie present" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }
    assert_response :success

    get "/api/v1/logged_in"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["logged_in"]
    assert body["user"].present?, "Expected user payload to be present"
  end
end
