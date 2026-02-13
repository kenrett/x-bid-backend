require "test_helper"

class CookieSessionAuthenticatorTest < ActiveSupport::TestCase
  test "prioritizes host-only session cookie over legacy cookie" do
    host_user = create_actor(role: :user)
    legacy_user = create_actor(role: :user)
    host_session = create_session_token_for(host_user)
    legacy_session = create_session_token_for(legacy_user)
    request = ActionDispatch::TestRequest.create

    with_env(Auth::CookieSessionAuthenticator::LEGACY_COOKIE_AUTH_ENV => "true") do
      request.cookie_jar.signed[Auth::CookieSessionAuthenticator::COOKIE_NAME] = host_session.id
      request.cookie_jar.signed[Auth::CookieSessionAuthenticator::LEGACY_COOKIE_NAME] = legacy_session.id

      resolved = Auth::CookieSessionAuthenticator.session_token_from_request(request)

      assert_equal host_session.id, resolved&.id
      assert_equal host_user.id, resolved&.user_id
    end
  end

  test "uses legacy session cookie only during migration window" do
    user = create_actor(role: :user)
    session_token = create_session_token_for(user)
    request = ActionDispatch::TestRequest.create

    with_env(Auth::CookieSessionAuthenticator::LEGACY_COOKIE_AUTH_ENV => "true") do
      request.cookie_jar.signed[Auth::CookieSessionAuthenticator::LEGACY_COOKIE_NAME] = session_token.id

      resolved = Auth::CookieSessionAuthenticator.session_token_from_request(request)

      assert_equal session_token.id, resolved&.id
      assert_equal user.id, resolved&.user_id
    end
  end

  test "rejects legacy parent-scoped session cookie once migration ends" do
    user = create_actor(role: :user)
    session_token = create_session_token_for(user)
    request = ActionDispatch::TestRequest.create

    with_env(Auth::CookieSessionAuthenticator::LEGACY_COOKIE_AUTH_ENV => nil) do
      request.cookie_jar.signed[Auth::CookieSessionAuthenticator::LEGACY_COOKIE_NAME] = session_token.id

      resolved = Auth::CookieSessionAuthenticator.session_token_from_request(request)

      assert_nil resolved
    end
  end

  private

  def create_session_token_for(user)
    SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )
  end
end
