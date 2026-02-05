require "test_helper"

class BearerAuthTest < ActionDispatch::IntegrationTest
  test "valid bearer token returns 200" do
    user = create_actor(role: :user)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
  end

  test "expired bearer token returns 401 with stable error shape" do
    user = create_actor(role: :user)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
    payload = {
      user_id: user.id,
      session_token_id: session_token.id,
      exp: 1.hour.ago.to_i,
      iat: 2.hours.ago.to_i,
      nbf: 2.hours.ago.to_i
    }
    token = encode_jwt(payload)

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "expired_session", body.dig("error", "details", "reason")
  end

  test "malformed bearer token returns 401 with stable error shape" do
    get "/api/v1/me", headers: { "Authorization" => "Bearer not-a-jwt" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
    assert_equal "bad_token_format", body.dig("error", "details", "reason")
  end

  test "revoked bearer token returns 401" do
    user = create_actor(role: :user)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
    session_token.revoke!
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_session", body.dig("error", "code")
    assert_equal "expired_session", body.dig("error", "details", "reason")
  end
end
