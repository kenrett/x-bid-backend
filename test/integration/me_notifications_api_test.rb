require "test_helper"
require "jwt"

class MeNotificationsApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user_notifications@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other_notifications@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(user: @other_user, token_digest: SessionToken.digest("raw2"), expires_at: 1.hour.from_now)

    @n1 = Notification.create!(user: @user, kind: :purchase_completed, data: { purchase_id: 1 }, created_at: 2.days.ago)
    @n2 = Notification.create!(user: @user, kind: :auction_won, data: { auction_id: 2 }, created_at: 1.day.ago)
    Notification.create!(user: @other_user, kind: :auction_won, data: { auction_id: 999 })
  end

  test "GET /api/v1/me/notifications returns only current user's notifications (newest first)" do
    get "/api/v1/me/notifications", headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal [ @n2.id, @n1.id ], body.map { |row| row.fetch("id") }
    assert_equal [ "auction_won", "purchase_completed" ], body.map { |row| row.fetch("kind") }
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
