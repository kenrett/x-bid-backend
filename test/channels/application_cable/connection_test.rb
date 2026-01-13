require "test_helper"
require "jwt"
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects when token is provided via query param" do
    user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

    connect params: { token: token }

    assert_equal user.id, connection.current_user.id
    assert_equal session_token.id, connection.current_session_token.id
  end

  test "rejects connection when token is missing" do
    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end

  test "rejects connection when token is invalid" do
    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect params: { token: "not-a-token" }
    end
  end

  test "rejects connection when session token is expired" do
    user = User.create!(name: "User", email_address: "expired@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.ago)

    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.ago.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect params: { token: token }
    end
  end

  test "rejects connection when session token is revoked" do
    user = User.create!(name: "User", email_address: "revoked@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    session_token.revoke!

    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect params: { token: token }
    end
  end
end
