require "test_helper"

class AdminNamespaceAuctionsApiTest < ActionDispatch::IntegrationTest
  def setup
    @auction = Auction.create!(
      title: "Admin Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active
    )
  end

  test "GET /api/v1/admin/auctions enforces role matrix" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/auctions", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      auctions = body["auctions"] || body["adminAuctions"] || body["admin_auctions"] || body
      auctions = auctions["auctions"] if auctions.is_a?(Hash) && auctions.key?("auctions")
      assert_kind_of Array, auctions
      first = auctions.first
      assert first.key?("id")
      assert first.key?("title")
    end
  end

  test "GET /api/v1/admin/auctions/:id enforces role matrix" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/auctions/#{@auction.id}", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      auction = body["auction"] || body
      assert_equal @auction.id, auction["id"]
      assert_equal "Admin Auction", auction["title"]
    end
  end
end
