require "test_helper"
require "jwt"

class AuctionWatchesApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    @auction = Auction.create!(
      title: "A",
      description: "desc",
      start_date: 2.days.ago,
      end_time: 1.day.from_now,
      current_price: BigDecimal("1.00"),
      status: :active
    )
  end

  test "watch/unwatch creates and removes watch" do
    assert_equal 0, AuctionWatch.where(user: @user, auction: @auction).count

    post "/api/v1/auctions/#{@auction.id}/watch", headers: auth_headers(@user, @session_token)
    assert_response :no_content
    assert_equal 1, AuctionWatch.where(user: @user, auction: @auction).count

    delete "/api/v1/auctions/#{@auction.id}/watch", headers: auth_headers(@user, @session_token)
    assert_response :no_content
    assert_equal 0, AuctionWatch.where(user: @user, auction: @auction).count
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)
    { "Authorization" => "Bearer #{token}" }
  end
end
