require "test_helper"

class AdminBidPacksApiTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/admin/bid-packs enforces role matrix" do
    pack = BidPack.create!(name: "Gold", description: "desc", bids: 100, price: 10.0, active: true)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/bid-packs", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      packs = body.is_a?(Array) ? body : (body["bidPacks"] || body["bid_packs"] || body)
      assert_kind_of Array, packs
      found = packs.find { |p| p["id"] == pack.id }
      assert found, "Expected response to include bid pack id=#{pack.id}"
      assert_equal "Gold", found["name"]
    end
  end

  test "GET /api/v1/admin/bid-packs/:id enforces role matrix and returns pricePerBid" do
    pack = BidPack.create!(name: "Silver", description: "desc", bids: 50, price: 5.0, active: true)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/bid-packs/#{pack.id}", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal "Silver", body["name"]
      assert_equal "$0.10", body["pricePerBid"]
    end
  end

  test "GET /api/v1/admin/bid-packs/new enforces role matrix" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/bid-packs/new", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert body.key?("pricePerBid")
    end
  end

  test "GET /api/v1/admin/bid-packs/:id/edit enforces role matrix" do
    pack = BidPack.create!(name: "Editable", description: "desc", bids: 10, price: 1.0, active: true)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/bid-packs/#{pack.id}/edit", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal pack.id, body["id"]
      assert_equal "Editable", body["name"]
    end
  end

  test "POST /api/v1/admin/bid-packs enforces role matrix and creates bid packs" do
    params = { bid_pack: { name: "Starter", description: "desc", bids: 10, price: 9.99, highlight: false } }

    each_role_case(required_role: :admin, success_status: 201) do |role:, headers:, expected_status:, success:, **|
      assert_difference("BidPack.count", success ? 1 : 0, "role=#{role}") do
        post "/api/v1/admin/bid-packs", params: params, headers: headers
      end

      assert_response expected_status

      next unless success

      body = JSON.parse(response.body)
      assert_equal "Starter", body["name"]
      assert body["id"].present?
    end
  end

  test "PATCH /api/v1/admin/bid-packs/:id enforces role matrix and updates bid packs" do
    pack = BidPack.create!(name: "Before", description: "desc", bids: 10, price: 1.0, active: true)
    params = { bid_pack: { name: "After" } }

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      patch "/api/v1/admin/bid-packs/#{pack.id}", params: params, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "After", JSON.parse(response.body)["name"]
        assert_equal "After", pack.reload.name
      else
        assert_equal "Before", pack.reload.name
      end
    end
  end

  test "POST /api/v1/admin/bid-packs returns validation errors for admins" do
    params = { bid_pack: { name: "", bids: 0, price: -5 } }

    each_role_case(required_role: :admin, success_status: 422) do |role:, headers:, expected_status:, success:, **|
      assert_no_difference("BidPack.count", "role=#{role}") do
        post "/api/v1/admin/bid-packs", params: params, headers: headers
      end

      assert_response expected_status

      next unless success

      body = JSON.parse(response.body)
      assert_equal "invalid_bid_pack", body.dig("error", "code").to_s
      assert_match(/Name can't be blank/, body.dig("error", "message"))
    end
  end

  test "DELETE /api/v1/admin/bid-packs/:id enforces role matrix and retires packs" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      pack = BidPack.create!(name: "To Retire", description: "desc", bids: 10, price: 1.0, active: true)

      delete "/api/v1/admin/bid-packs/#{pack.id}", headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "retired", body["status"]
        assert_equal false, body["active"]
        assert_equal pack.id, body["id"]
        assert_equal "retired", pack.reload.status
      else
        assert_equal "active", pack.reload.status
      end
    end
  end

  test "DELETE /api/v1/admin/bid-packs/:id is protected against double-retire" do
    pack = BidPack.create!(name: "Already Retired", description: "desc", bids: 100, price: 10.0, active: false)

    admin = create_actor(role: :admin)
    delete "/api/v1/admin/bid-packs/#{pack.id}", headers: auth_headers_for(admin)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "Bid pack already retired", body.dig("error", "message")
  end

  test "blocks hard delete through the model" do
    pack = BidPack.create!(name: "Bronze", description: "desc", bids: 10, price: 1.0, active: true)

    assert_no_difference("BidPack.count") do
      assert_not pack.destroy
    end

    assert_includes pack.errors.full_messages, "Bid packs cannot be hard-deleted; retire instead"
    assert pack.reload.active?
  end
end
