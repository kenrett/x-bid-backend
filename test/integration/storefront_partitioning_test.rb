require "test_helper"

class StorefrontPartitioningTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.write("maintenance_mode.enabled", false)
    MaintenanceSetting.global.update!(enabled: false)

    @main_auction = Auction.create!(
      title: "Main Partition Auction",
      description: "Main partition",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )

    @afterdark_auction = Auction.create!(
      title: "Afterdark Partition Auction",
      description: "Afterdark partition",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      storefront_key: "afterdark",
      is_marketplace: false,
      is_adult: false
    )
  end

  test "index only returns auctions in the current storefront partition" do
    host!("biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @main_auction.id)
    refute includes_auction_id?(response.body, @afterdark_auction.id)

    host!("afterdark.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @afterdark_auction.id)
    refute includes_auction_id?(response.body, @main_auction.id)
  end

  test "show returns not found for auctions outside the storefront partition" do
    host!("afterdark.biddersweet.app")
    get "/api/v1/auctions/#{@afterdark_auction.id}"
    assert_response :success

    host!("biddersweet.app")
    get "/api/v1/auctions/#{@afterdark_auction.id}"
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s
  end

  test "bid creation is blocked outside storefront partition and allowed in matching storefront" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)
    Credits::Apply.apply!(
      user: user,
      reason: "seed_grant",
      amount: 1,
      idempotency_key: "test:storefront_partitioning:seed_grant:#{user.id}"
    )

    host!("biddersweet.app")
    assert_no_difference -> { Bid.where(auction: @afterdark_auction, user: user).count } do
      post "/api/v1/auctions/#{@afterdark_auction.id}/bids", headers: auth_headers_for(user)
    end
    assert_response :not_found
    assert_equal 1, user.reload.bid_credits

    host!("afterdark.biddersweet.app")
    post "/api/v1/auctions/#{@afterdark_auction.id}/bids", headers: auth_headers_for(user)
    assert_response :success
    assert_equal 0, user.reload.bid_credits
    assert_equal 1, Bid.where(auction: @afterdark_auction, user: user).count
  end

  test "index response varies by storefront key for shared caches" do
    host!("biddersweet.app")
    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "main" }
    assert_response :success
    main_etag = response.headers["ETag"]
    vary_values = response.headers["Vary"].to_s.split(",").map(&:strip)
    assert_includes vary_values, "X-Storefront-Key"
    assert main_etag.present?

    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "main", "If-None-Match" => main_etag }
    assert_response :not_modified

    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "afterdark", "If-None-Match" => main_etag }
    assert_response :success
    refute_equal main_etag, response.headers["ETag"]
  end

  test "storefront reassignment is reflected immediately in storefront-scoped list and detail visibility" do
    auction = Auction.create!(
      title: "Reassign Visibility",
      description: "Desc",
      start_date: 1.hour.ago,
      end_time: 1.hour.from_now,
      current_price: 5.0,
      status: :active,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )

    admin = create_actor(role: :admin)
    host!("biddersweet.app")
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "marketplace" } },
        headers: auth_headers_for(admin)
    assert_response :success

    host!("biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    refute includes_auction_id?(response.body, auction.id)
    get "/api/v1/auctions/#{auction.id}"
    assert_response :not_found

    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, auction.id)
    get "/api/v1/auctions/#{auction.id}"
    assert_response :success
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
