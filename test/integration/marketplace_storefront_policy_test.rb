require "test_helper"

class MarketplaceStorefrontPolicyTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.write("maintenance_mode.enabled", false)
    MaintenanceSetting.global.update!(enabled: false)

    @main_auction = Auction.create!(
      title: "Main",
      description: "main",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      is_marketplace: false,
      is_adult: false
    )

    @marketplace_auction = Auction.create!(
      title: "Marketplace",
      description: "marketplace",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      is_marketplace: true,
      is_adult: false
    )
  end

  test "marketplace listing returns only marketplace auctions (host mapping + header override)" do
    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @marketplace_auction.id)
    refute includes_auction_id?(response.body, @main_auction.id)

    host!("biddersweet.app")
    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "marketplace" }
    assert_response :success
    assert includes_auction_id?(response.body, @marketplace_auction.id)
    refute includes_auction_id?(response.body, @main_auction.id)
  end

  test "main listing excludes marketplace-only auctions" do
    host!("biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @main_auction.id)
    refute includes_auction_id?(response.body, @marketplace_auction.id)
  end

  test "main cannot fetch marketplace auction detail but marketplace can" do
    host!("biddersweet.app")
    get "/api/v1/auctions/#{@marketplace_auction.id}"
    assert_response :not_found

    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions/#{@marketplace_auction.id}"
    assert_response :success
  end

  test "main cannot fetch marketplace bid history but marketplace can" do
    winning_user = create_actor(role: :user)
    bid = Bid.create!(user: winning_user, auction: @marketplace_auction, amount: 11.0, created_at: 1.minute.ago)
    @marketplace_auction.update!(winning_user: winning_user)

    host!("biddersweet.app")
    get "/api/v1/auctions/#{@marketplace_auction.id}/bid_history"
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s

    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions/#{@marketplace_auction.id}/bid_history"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal winning_user.id, body.dig("auction", "winning_user_id")
    assert_equal winning_user.name, body.dig("auction", "winning_user_name")
    assert_equal bid.id, body.fetch("bids").first.fetch("id")
    assert_equal winning_user.name, body.fetch("bids").first.fetch("username")
  end

  test "non-admin cannot create auctions (curated-only guardrail)" do
    user = create_actor(role: :user)
    headers = auth_headers_for(user)

    post "/api/v1/auctions",
         params: { auction: { title: "Nope", description: "Nope" } },
         headers: headers

    assert_response :forbidden
  end

  test "main storefront cannot place a bid on marketplace inventory" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    Credits::Apply.apply!(
      user: user,
      reason: "seed_grant",
      amount: 1,
      idempotency_key: "test:marketplace_storefront_policy:main_bid_blocked:#{user.id}"
    )

    host!("biddersweet.app")
    assert_no_difference -> { Bid.where(auction: @marketplace_auction).count } do
      post "/api/v1/auctions/#{@marketplace_auction.id}/bids", headers: auth_headers_for(user)
    end

    assert_response :not_found
    assert_equal 1, user.reload.bid_credits
    assert_equal 0, CreditTransaction.where(user: user, auction: @marketplace_auction, reason: "bid_placed").count
  end

  test "marketplace storefront can place a bid on marketplace inventory" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    Credits::Apply.apply!(
      user: user,
      reason: "seed_grant",
      amount: 1,
      idempotency_key: "test:marketplace_storefront_policy:marketplace_bid_allowed:#{user.id}"
    )

    host!("marketplace.biddersweet.app")
    post "/api/v1/auctions/#{@marketplace_auction.id}/bids", headers: auth_headers_for(user)

    assert_response :success
    assert_equal 0, user.reload.bid_credits
    assert_equal 1, Bid.where(auction: @marketplace_auction, user: user).count
  end

  private

  def includes_auction_id?(json, auction_id)
    parsed = JSON.parse(json)
    ids = []

    walk = lambda do |value|
      case value
      when Array
        value.each { |v| walk.call(v) }
      when Hash
        if value.key?("id") && (value.key?("title") || value.key?("status")) && (value.key?("end_time") || value.key?("current_price"))
          ids << value["id"].to_i
        end
        value.each_value { |v| walk.call(v) }
      end
    end

    walk.call(parsed)
    ids.include?(auction_id.to_i)
  end
end
