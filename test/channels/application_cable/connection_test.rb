require "test_helper"
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects when cookie session is provided" do
    user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    session_token = SessionToken.create!(user: user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    cookies.signed[:bs_session_id] = session_token.id
    connect

    assert_equal user.id, connection.current_user.id
    assert_equal session_token.id, connection.current_session_token.id
  end

  test "rejects connection when cookie is missing" do
    assert_raises(ActionCable::Connection::Authorization::UnauthorizedError) do
      connect
    end
  end
end
