require "test_helper"
require "jwt"

class AuthorizationBoundariesTest < ActionDispatch::IntegrationTest
  test "normal user cannot access /api/v1/admin/* endpoints" do
    user = create_actor(role: :user)
    headers = auth_headers_for(user)

    [
      -> { get "/api/v1/admin/payments", headers: headers },
      -> { get "/api/v1/admin/bid-packs", headers: headers },
      -> { post "/api/v1/admin/audit", params: { action: "noop", target_type: "User", target_id: 1, payload: {} }, headers: headers },
      -> { get "/api/v1/admin/users", headers: headers }
    ].each do |request|
      request.call
      assert_forbidden
      body = JSON.parse(response.body)
      assert_equal "forbidden", body.dig("error", "code").to_s
    end
  end

  test "admin cannot grant superadmin role (superadmin only)" do
    admin = create_actor(role: :admin)
    target = create_actor(role: :user)

    post "/api/v1/admin/users/#{target.id}/grant_superadmin", headers: auth_headers_for(admin)

    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body.dig("error", "code").to_s
    assert_match(/superadmin/i, body.dig("error", "message"))
    assert_equal "user", target.reload.role
  end

  test "IDOR: user cannot revoke another user's session token" do
    alice = create_actor(role: :user)
    bob = create_actor(role: :user)

    alice_headers, = auth_headers_and_session_token_for(alice)
    _, bob_session_token = auth_headers_and_session_token_for(bob)

    delete "/api/v1/account/sessions/#{bob_session_token.id}", headers: alice_headers

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s
  end

  test "IDOR: user cannot see another user's account export" do
    alice = create_actor(role: :user)
    bob = create_actor(role: :user)

    bob.account_exports.create!(
      status: :ready,
      requested_at: Time.current,
      ready_at: Time.current,
      download_url: "https://example.com/export",
      payload: { "dummy" => true }
    )

    get "/api/v1/account/data/export", headers: auth_headers_for(alice)

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body.fetch("export"), "Expected export to be scoped to current user"
  end

  test "ban/disable revokes sessions immediately" do
    superadmin = create_actor(role: :superadmin)
    victim = create_actor(role: :user)

    victim_headers, victim_session_token = auth_headers_and_session_token_for(victim)

    get "/api/v1/account", headers: victim_headers
    assert_response :success

    post "/api/v1/admin/users/#{victim.id}/ban", headers: auth_headers_for(superadmin)
    assert_response :success
    assert victim.reload.disabled?
    assert victim_session_token.reload.revoked_at.present?

    get "/api/v1/account", headers: victim_headers
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_session", body.dig("error", "code").to_s
  end

  private

  def auth_headers_and_session_token_for(actor, expires_at: 1.hour.from_now)
    session_token = SessionToken.create!(
      user: actor,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: expires_at
    )

    payload = { user_id: actor.id, session_token_id: session_token.id, exp: expires_at.to_i }
    jwt = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

    [ { "Authorization" => "Bearer #{jwt}" }, session_token ]
  end
end
