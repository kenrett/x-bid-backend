require "test_helper"

class OptionalSessionTest < ActiveSupport::TestCase
  test "returns active session token from signed cookie" do
    user = create_actor(role: :user)
    session_token = create_session_token_for(user)
    request = ActionDispatch::TestRequest.create
    request.cookie_jar.signed[Auth::CookieSessionAuthenticator::COOKIE_NAME] = session_token.id

    resolved = Auth::OptionalSession.call(request)

    assert_equal session_token.id, resolved.session_token&.id
    assert_equal user.id, resolved.user&.id
  end

  test "falls back to bearer session token when cookie session is absent" do
    user = create_actor(role: :user)
    session_token = create_session_token_for(user)
    request = ActionDispatch::TestRequest.create
    request.headers["Authorization"] = "Bearer #{jwt_for(session_token)}"

    resolved = Auth::OptionalSession.call(request)

    assert_equal session_token.id, resolved.session_token&.id
    assert_equal user.id, resolved.user&.id
  end

  test "prefers cookie session token over bearer token" do
    cookie_user = create_actor(role: :user)
    bearer_user = create_actor(role: :user)
    cookie_session_token = create_session_token_for(cookie_user)
    bearer_session_token = create_session_token_for(bearer_user)
    request = ActionDispatch::TestRequest.create
    request.cookie_jar.signed[Auth::CookieSessionAuthenticator::COOKIE_NAME] = cookie_session_token.id
    request.headers["Authorization"] = "Bearer #{jwt_for(bearer_session_token)}"

    resolved = Auth::OptionalSession.call(request)

    assert_equal cookie_session_token.id, resolved.session_token&.id
    assert_equal cookie_user.id, resolved.user&.id
  end

  test "returns nil session token and user when no auth is present" do
    resolved = Auth::OptionalSession.call(ActionDispatch::TestRequest.create)

    assert_nil resolved.session_token
    assert_nil resolved.user
  end

  private

  def create_session_token_for(user)
    SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
  end

  def jwt_for(session_token)
    encode_jwt(
      {
        user_id: session_token.user_id,
        session_token_id: session_token.id,
        exp: session_token.expires_at.to_i
      }
    )
  end
end
