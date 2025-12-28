require "test_helper"
require "jwt"

class MeWinsClaimApiTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(name: "User", email_address: "user_claim@example.com", password: "password", bid_credits: 0)
    @other_user = User.create!(name: "Other", email_address: "other_claim@example.com", password: "password", bid_credits: 0)

    @session_token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    @other_session_token = SessionToken.create!(
      user: @other_user,
      token_digest: SessionToken.digest("raw2"),
      expires_at: 1.hour.from_now
    )

    @auction = Auction.create!(
      title: "Win",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: @user
    )
    @bid = Bid.create!(user: @user, auction: @auction, amount: BigDecimal("10.00"))
    @settlement = AuctionSettlement.create!(
      auction: @auction,
      winning_user: @user,
      winning_bid: @bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    @fulfillment = AuctionFulfillment.create!(auction_settlement: @settlement, user: @user)
  end

  test "POST /api/v1/me/wins/:auction_id/claim captures address and transitions to claimed" do
    post "/api/v1/me/wins/#{@auction.id}/claim",
         params: {
           shipping_address: {
             name: "User",
             line1: "123 Main",
             line2: "Apt 4",
             city: "Portland",
             state: "OR",
             postal_code: "97201",
             country: "US"
           }
         },
         headers: auth_headers(@user, @session_token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "claimed", body.fetch("fulfillment_status")
    assert_equal "123 Main", body.dig("fulfillment", "address", "line1")

    @fulfillment.reload
    assert_equal "claimed", @fulfillment.status
    assert_equal "97201", @fulfillment.shipping_address.fetch("postal_code")
  end

  test "cannot claim twice" do
    post "/api/v1/me/wins/#{@auction.id}/claim",
         params: { shipping_address: valid_address },
         headers: auth_headers(@user, @session_token)
    assert_response :success

    post "/api/v1/me/wins/#{@auction.id}/claim",
         params: { shipping_address: valid_address },
         headers: auth_headers(@user, @session_token)
    assert_response :unprocessable_content
  end

  test "cannot claim another user's win" do
    other_auction = Auction.create!(
      title: "Other Win",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: @other_user
    )
    other_bid = Bid.create!(user: @other_user, auction: other_auction, amount: BigDecimal("10.00"))
    other_settlement = AuctionSettlement.create!(
      auction: other_auction,
      winning_user: @other_user,
      winning_bid: other_bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    AuctionFulfillment.create!(auction_settlement: other_settlement, user: @other_user)

    post "/api/v1/me/wins/#{other_auction.id}/claim",
         params: { shipping_address: valid_address },
         headers: auth_headers(@user, @session_token)
    assert_response :not_found
  end

  test "invalid address rejected" do
    post "/api/v1/me/wins/#{@auction.id}/claim",
         params: { shipping_address: { line1: "123 Main" } },
         headers: auth_headers(@user, @session_token)

    assert_response :unprocessable_content
    @fulfillment.reload
    assert_equal "pending", @fulfillment.status
  end

  private

  def valid_address
    {
      name: "User",
      line1: "123 Main",
      city: "Portland",
      state: "OR",
      postal_code: "97201",
      country: "US"
    }
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
