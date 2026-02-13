require "test_helper"
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects when cookie session is provided" do
    user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    cookies.signed[Auth::CookieSessionAuthenticator::COOKIE_NAME] = session_token.id
    connect

    assert_equal user.id, connection.current_user.id
    assert_equal session_token.id, connection.current_session_token.id
  end

  test "rejects connection when cookie is missing" do
    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end

  test "diagnostics read cable_session from signed cookies" do
    user = User.create!(name: "User", email_address: "signed-cable@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    cookies.signed[Auth::CookieSessionAuthenticator::COOKIE_NAME] = session_token.id
    cookies.signed[:cable_session] = session_token.id
    connect

    context = connection.send(:connection_log_context)
    assert_equal true, context[:cable_session_cookie_present]
  end

  test "connects with legacy browser session cookie during migration window" do
    user = User.create!(name: "User", email_address: "legacy-cookie@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    with_env(Auth::CookieSessionAuthenticator::LEGACY_COOKIE_AUTH_ENV => "true") do
      cookies.signed[Auth::CookieSessionAuthenticator::LEGACY_COOKIE_NAME] = session_token.id
      connect
    end

    assert_equal user.id, connection.current_user.id
    assert_equal session_token.id, connection.current_session_token.id
  end

  test "rejects legacy browser session cookie when migration window is closed" do
    user = User.create!(name: "User", email_address: "legacy-cookie-closed@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    with_env(Auth::CookieSessionAuthenticator::LEGACY_COOKIE_AUTH_ENV => nil) do
      cookies.signed[Auth::CookieSessionAuthenticator::LEGACY_COOKIE_NAME] = session_token.id

      assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
        connect
      end
    end
  end
end
