require "test_helper"

class HomepageCachingHeadersTest < ActionDispatch::IntegrationTest
  test "GET / sets public caching headers and supports If-None-Match" do
    Auction.create!(
      title: "Test auction",
      description: "Example",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 0,
      status: :active
    )

    get "/"
    assert_response :success
    assert response.headers["ETag"].present?
    assert_includes response.headers["Cache-Control"], "public"
    assert_includes response.headers["Cache-Control"], "max-age="

    etag = response.headers["ETag"]
    get "/", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "GET /api/v1/bid_packs sets public caching headers and supports If-None-Match" do
    BidPack.create!(
      name: "Starter",
      price: 9.99,
      bids: 10,
      status: :active
    )

    get "/api/v1/bid_packs"
    assert_response :success
    assert response.headers["ETag"].present?
    assert_includes response.headers["Cache-Control"], "public"
    assert_includes response.headers["Cache-Control"], "max-age="

    etag = response.headers["ETag"]
    get "/api/v1/bid_packs", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end
end
