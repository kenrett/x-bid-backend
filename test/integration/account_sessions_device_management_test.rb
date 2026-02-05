require "test_helper"
require "jwt"

class AccountSessionsDeviceManagementTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/account/sessions lists only the current user's active sessions" do
    user_a = create_actor(role: :user)
    user_b = create_actor(role: :user)

    current_a = SessionToken.create!(user: user_a, token_digest: SessionToken.digest("a1"), expires_at: 1.hour.from_now, user_agent: "UA-A1")
    other_a = SessionToken.create!(user: user_a, token_digest: SessionToken.digest("a2"), expires_at: 1.hour.from_now, user_agent: "UA-A2")
    SessionToken.create!(user: user_b, token_digest: SessionToken.digest("b1"), expires_at: 1.hour.from_now, user_agent: "UA-B1")

    get "/api/v1/account/sessions", headers: auth_headers(user_a, current_a)
    assert_response :success
    sessions = JSON.parse(response.body).fetch("sessions")
    ids = sessions.map { |s| s.fetch("id") }

    assert_includes ids, current_a.id
    assert_includes ids, other_a.id
    refute_includes ids, user_b.session_tokens.first.id

    current_payload = sessions.find { |s| s["id"] == current_a.id }
    assert_equal true, current_payload["current"]
    assert current_payload.key?("created_at")
    assert current_payload.key?("last_seen_at")
    assert current_payload.key?("user_agent_summary")
  end

  test "DELETE /api/v1/account/sessions/:id revokes only the target session" do
    user = create_actor(role: :user)
    current_session = SessionToken.create!(user: user, token_digest: SessionToken.digest("cur"), expires_at: 1.hour.from_now)
    other_session = SessionToken.create!(user: user, token_digest: SessionToken.digest("oth"), expires_at: 1.hour.from_now)

    delete "/api/v1/account/sessions/#{other_session.id}", headers: auth_headers(user, current_session)
    assert_response :success
    assert other_session.reload.revoked_at.present?
    assert_nil current_session.reload.revoked_at
  end

  test "DELETE /api/v1/account/sessions revokes all other sessions but not current" do
    user = create_actor(role: :user)
    current_session = SessionToken.create!(user: user, token_digest: SessionToken.digest("cur2"), expires_at: 1.hour.from_now)
    other_session_1 = SessionToken.create!(user: user, token_digest: SessionToken.digest("oth21"), expires_at: 1.hour.from_now)
    other_session_2 = SessionToken.create!(user: user, token_digest: SessionToken.digest("oth22"), expires_at: 1.hour.from_now)

    delete "/api/v1/account/sessions", headers: auth_headers(user, current_session)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "revoked", body["status"]
    assert_equal 2, body["sessions_revoked"]

    assert other_session_1.reload.revoked_at.present?
    assert other_session_2.reload.revoked_at.present?
    assert_nil current_session.reload.revoked_at
  end

  test "authenticated request updates last_seen_at (debounced)" do
    user = create_actor(role: :user)
    token = SessionToken.create!(user: user, token_digest: SessionToken.digest("seen"), expires_at: 1.hour.from_now, last_seen_at: nil)

    get "/api/v1/account/sessions", headers: auth_headers(user, token)
    assert_response :success

    assert token.reload.last_seen_at.present?
  end

  private

  def auth_headers(user, session_token, exp: 1.hour.from_now.to_i)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: exp }
    jwt = encode_jwt(payload)
    { "Authorization" => "Bearer #{jwt}" }
  end
end
