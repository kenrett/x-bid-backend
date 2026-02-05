require "test_helper"
require "securerandom"
require "jwt"

class AdultCatalogPolicyTest < ActionDispatch::IntegrationTest
  def setup
    Rails.cache.write("maintenance_mode.enabled", false)
    MaintenanceSetting.global.update!(enabled: false)

    @normal_auction = Auction.create!(
      title: "Normal",
      description: "normal",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      is_adult: false
    )

    @adult_auction = Auction.create!(
      title: "Adult",
      description: "adult",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active,
      is_adult: true
    )
  end

  test "main and marketplace listings never include adult auctions (host mapping + header override)" do
    host!("biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    refute includes_auction_id?(response.body, @adult_auction.id)

    host!("marketplace.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    refute includes_auction_id?(response.body, @adult_auction.id)

    host!("biddersweet.app")
    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "marketplace" }
    assert_response :success
    refute includes_auction_id?(response.body, @adult_auction.id)
  end

  test "afterdark listings can include adult auctions (host mapping + header override)" do
    host!("afterdark.biddersweet.app")
    get "/api/v1/auctions"
    assert_response :success
    assert includes_auction_id?(response.body, @adult_auction.id)

    host!("biddersweet.app")
    get "/api/v1/auctions", headers: { "X-Storefront-Key" => "afterdark" }
    assert_response :success
    assert includes_auction_id?(response.body, @adult_auction.id)
  end

  test "main cannot fetch adult auction detail (safe 404)" do
    host!("biddersweet.app")
    get "/api/v1/auctions/#{@adult_auction.id}"
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s
  end

  test "afterdark adult detail requires age gate acceptance and succeeds after accepting" do
    host!("afterdark.biddersweet.app")
    get "/api/v1/auctions/#{@adult_auction.id}"
    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "AGE_GATE_REQUIRED", body.dig("error", "code").to_s

    host!("biddersweet.app")
    get "/api/v1/auctions/#{@adult_auction.id}", headers: { "X-Storefront-Key" => "afterdark" }
    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "AGE_GATE_REQUIRED", body.dig("error", "code").to_s

    user = create_actor(role: :user)
    session_token, jwt = session_jwt_for(user)

    host!("afterdark.biddersweet.app")
    post "/api/v1/age_gate/accept",
         headers: {
           "Authorization" => "Bearer #{jwt}"
         }
    assert_response :no_content
    assert session_token.reload.age_verified_at.present?

    host!("afterdark.biddersweet.app")
    get "/api/v1/auctions/#{@adult_auction.id}",
        headers: {
          "Authorization" => "Bearer #{jwt}"
        }
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

  def session_jwt_for(user, expires_at: 1.hour.from_now)
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: expires_at
    )

    payload = { user_id: user.id, session_token_id: session_token.id, exp: expires_at.to_i }
    jwt = encode_jwt(payload)

    [ session_token, jwt ]
  end
end
