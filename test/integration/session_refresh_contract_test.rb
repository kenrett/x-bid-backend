require "test_helper"

class SessionRefreshContractTest < ActionDispatch::IntegrationTest
  test "valid refresh rotates tokens and returns stable session payload" do
    user = create_actor(role: :user)
    old_session_token, refresh_token = SessionToken.generate_for(user: user)

    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }

    assert_response :success
    body = JSON.parse(response.body)

    assert body["access_token"].present?
    assert body["refresh_token"].present?
    assert body["session_token_id"].present?
    assert body["user"].is_a?(Hash)
    assert_equal false, body.dig("user", "is_admin")
    assert_equal false, body.dig("user", "is_superuser")

    assert old_session_token.reload.revoked_at.present?
    assert_equal true, SessionToken.find_by(id: body["session_token_id"]).active?
  end

  test "reusing the same refresh token fails with 401" do
    user = create_actor(role: :user)
    _old_session_token, refresh_token = SessionToken.generate_for(user: user)

    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }
    assert_response :success

    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_session", body.dig("error", "code").to_s
  end

  test "disabled user refresh fails with 403 and revokes session token" do
    user = create_actor(role: :user)
    user.update!(status: :disabled)
    session_token, refresh_token = SessionToken.generate_for(user: user)

    post "/api/v1/session/refresh", params: { refresh_token: refresh_token }

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "account_disabled", body.dig("error", "code").to_s
    assert session_token.reload.revoked_at.present?
  end
end
