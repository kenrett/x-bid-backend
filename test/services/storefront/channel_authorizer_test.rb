require "test_helper"

class StorefrontChannelAuthorizerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      name: "User",
      email_address: "authorizer@example.com",
      password: "password",
      bid_credits: 0
    )
    @session_token = SessionToken.create!(
      user: @user,
      token_digest: SessionToken.digest("authorizer-token"),
      expires_at: 1.hour.from_now
    )

    @main_auction = Auction.create!(
      title: "Main",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: false,
      is_adult: false
    )
    @marketplace_auction = Auction.create!(
      title: "Marketplace",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: true,
      is_adult: false
    )
    @adult_auction = Auction.create!(
      title: "Adult",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: false,
      is_adult: true
    )
  end

  test "allows in-scope auction subscription" do
    allowed = Storefront::ChannelAuthorizer.can_subscribe_to_auction?(
      auction: @main_auction,
      storefront_key: "main",
      session_token: @session_token
    )

    assert allowed
  end

  test "rejects marketplace auction for main storefront" do
    allowed = Storefront::ChannelAuthorizer.can_subscribe_to_auction?(
      auction: @marketplace_auction,
      storefront_key: "main",
      session_token: @session_token
    )

    refute allowed
  end

  test "rejects adult auction for afterdark when age gate not accepted" do
    allowed = Storefront::ChannelAuthorizer.can_subscribe_to_auction?(
      auction: @adult_auction,
      storefront_key: "afterdark",
      session_token: @session_token
    )

    refute allowed
  end

  test "allows adult auction for afterdark when age gate accepted" do
    @session_token.update!(age_verified_at: Time.current)

    allowed = Storefront::ChannelAuthorizer.can_subscribe_to_auction?(
      auction: @adult_auction,
      storefront_key: "afterdark",
      session_token: @session_token
    )

    assert allowed
  end
end
