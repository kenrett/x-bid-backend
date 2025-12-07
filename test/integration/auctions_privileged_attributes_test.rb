require "test_helper"
require "jwt"

class AuctionsPrivilegedAttributesTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user_priv@example.com", password: "password", role: :user, bid_credits: 0)
    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @auction = Auction.create!(
      title: "Privileged Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :pending
    )
  end

  test "non-admin cannot update privileged auction attributes" do
    original_attrs = @auction.slice(:status, :start_date, :end_time, :current_price, :winning_user_id)

    put "/api/v1/auctions/#{@auction.id}",
      params: {
        auction: {
          status: "active",
          start_date: 2.days.from_now,
          end_time: 3.days.from_now,
          current_price: 999.0,
          winning_user_id: User.create!(name: "Hacker", email_address: "hacker@example.com", password: "password", bid_credits: 0).id
        }
      },
      headers: auth_headers

    assert_response :forbidden
    @auction.reload
    assert_equal original_attrs[:status], @auction.status
    assert_in_delta original_attrs[:start_date], @auction.start_date, 0.001
    assert_in_delta original_attrs[:end_time], @auction.end_time, 0.001
    assert_equal original_attrs[:current_price], @auction.current_price
    assert_nil @auction.winning_user_id
  end

  test "non-admin cannot retire auction" do
    delete "/api/v1/auctions/#{@auction.id}", headers: auth_headers

    assert_response :forbidden
    assert_not_equal "inactive", @auction.reload.status
  end

  private

  def auth_headers
    payload = { user_id: @user.id, session_token_id: @session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
