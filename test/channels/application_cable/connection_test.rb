require "test_helper"
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects when cable session cookie is valid" do
    user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    cookies.signed[:cable_session] = session_token.id
    connect

    assert_equal user.id, connection.current_user.id
    assert_equal session_token.id, connection.current_session_token.id
  end

  test "rejects connection when token is missing" do
    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end

  test "rejects connection when cookie refers to missing session token" do
    cookies.signed[:cable_session] = 999_999

    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end

  test "rejects connection when session token is expired" do
    user = User.create!(name: "User", email_address: "expired@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.ago)

    cookies.signed[:cable_session] = session_token.id

    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end

  test "rejects connection when session token is revoked" do
    user = User.create!(name: "User", email_address: "revoked@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    session_token.revoke!

    cookies.signed[:cable_session] = session_token.id

    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end
end
