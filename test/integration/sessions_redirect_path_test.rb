require "test_helper"
require "jwt"

class SessionsRedirectPathTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0, role: :user)
    @superadmin = User.create!(name: "Super", email_address: "super@example.com", password: "password", bid_credits: 0, role: :superadmin)
  end

  test "superadmin login includes redirect_path" do
    post "/api/v1/login", params: { session: { email_address: @superadmin.email_address, password: "password" } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["redirect_path"]
  end

  test "regular user login has nil redirect_path" do
    post "/api/v1/login", params: { session: { email_address: @user.email_address, password: "password" } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["redirect_path"]
  end
end
