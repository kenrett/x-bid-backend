require "test_helper"

class AuctionChannelTest < ActionCable::Channel::TestCase
  def setup
    @user = User.create!(
      name: "User",
      email_address: "user@example.com",
      password: "password",
      bid_credits: 0
    )
    @session_token = SessionToken.create!(
      user: @user,
      token_digest: SessionToken.digest("raw-token"),
      expires_at: 1.hour.from_now
    )

    @main_auction = Auction.create!(
      title: "Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: false,
      is_adult: false
    )

    @marketplace_auction = Auction.create!(
      title: "Marketplace Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: true,
      is_adult: false
    )

    @adult_auction = Auction.create!(
      title: "Adult Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      is_marketplace: false,
      is_adult: true
    )
  end

  test "streams storefront-scoped list feed when stream param is list" do
    stub_storefront_connection(storefront_key: "marketplace")
    subscribe(stream: "list")
    assert subscription.confirmed?
    assert stream_exists_for?(list_stream_name("marketplace"))
  end

  test "rejects subscription when auction_id is missing" do
    stub_storefront_connection(storefront_key: "main")
    subscribe
    assert subscription.rejected?
  end

  test "rejects subscription when auction does not exist" do
    stub_storefront_connection(storefront_key: "main")
    subscribe(auction_id: 999_999)
    assert subscription.rejected?
  end

  test "streams for valid auction in storefront scope" do
    stub_storefront_connection(storefront_key: "main")
    subscribe(auction_id: @main_auction.id)
    assert subscription.confirmed?
    assert_has_stream_for @main_auction
  end

  test "rejects subscription when auction is out of storefront scope" do
    stub_storefront_connection(storefront_key: "main")
    subscribe(auction_id: @marketplace_auction.id)
    assert subscription.rejected?
  end

  test "rejects adult auction without age-verified session" do
    stub_storefront_connection(storefront_key: "afterdark")
    subscribe(auction_id: @adult_auction.id)
    assert subscription.rejected?
  end

  test "allows adult auction with age-verified session" do
    @session_token.update!(age_verified_at: Time.current)
    stub_storefront_connection(storefront_key: "afterdark")
    subscribe(auction_id: @adult_auction.id)
    assert subscription.confirmed?
    assert_has_stream_for @adult_auction
  end

  test "stop_stream stops stream" do
    stub_storefront_connection(storefront_key: "main")
    subscribe(auction_id: @main_auction.id)
    perform :stop_stream
    refute stream_exists_for?(@main_auction)
  end

  test "start_stream resumes stream" do
    stub_storefront_connection(storefront_key: "main")
    subscribe(auction_id: @main_auction.id)
    perform :stop_stream
    refute stream_exists_for?(@main_auction)
    perform :start_stream
    assert stream_exists_for?(@main_auction)
  end

  private

  def stream_exists_for?(target)
    streams = subscription.send(:streams)
    expected = target.is_a?(Auction) ? subscription.send(:broadcasting_for, target) : target
    streams&.include?(expected)
  end

  def list_stream_name(storefront_key)
    AuctionChannel.list_stream_for(storefront_key)
  end

  def stub_storefront_connection(storefront_key:)
    stub_connection(
      current_user: @user,
      current_session_token: @session_token,
      current_storefront_key: storefront_key
    )
  end
end
