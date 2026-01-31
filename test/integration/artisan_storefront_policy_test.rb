require "test_helper"

class ArtisanStorefrontPolicyTest < ActionDispatch::IntegrationTest
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
      is_artisan: false,
      is_adult: false
    )

    @artisan_auction = Auction.create!(
      title: "Marketplace",
      description: "marketplace",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      is_artisan: true,
      is_adult: false
    )
  end

  test "marketplace listing returns only artisan auctions (host mapping + header override)" do
    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @artisan_auction.id)
    refute includes_auction_id?(response.body, @main_auction.id)

    host!("biddersweet.app")
    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "marketplace" }
    assert_response :success
    assert includes_auction_id?(response.body, @artisan_auction.id)
    refute includes_auction_id?(response.body, @main_auction.id)
  end

  test "main listing excludes artisan-only auctions" do
    host!("biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @main_auction.id)
    refute includes_auction_id?(response.body, @artisan_auction.id)
  end

  test "main cannot fetch artisan auction detail but marketplace can" do
    host!("biddersweet.app")
    get "/api/v1/auctions/#{@artisan_auction.id}"
    assert_response :not_found

    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions/#{@artisan_auction.id}"
    assert_response :success
  end

  test "non-admin cannot create auctions (curated-only guardrail)" do
    user = create_actor(role: :user)
    headers = auth_headers_for(user)

    post "/api/v1/auctions",
         params: { auction: { title: "Nope", description: "Nope" } },
         headers: headers

    assert_response :forbidden
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
