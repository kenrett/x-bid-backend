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

  test "GET /api/v1/admin/auctions still returns mixed statuses for admin routes" do
    pending = Auction.create!(
      title: "Pending Auction",
      description: "Desc",
      start_date: 2.days.from_now,
      end_time: 3.days.from_now,
      current_price: 1.0,
      status: :pending
    )
    ended = Auction.create!(
      title: "Ended Auction",
      description: "Desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: 1.0,
      status: :ended
    )
    cancelled = Auction.create!(
      title: "Cancelled Auction",
      description: "Desc",
      start_date: 4.days.ago,
      end_time: 3.days.ago,
      current_price: 1.0,
      status: :cancelled
    )
    inactive = Auction.create!(
      title: "Inactive Auction",
      description: "Desc",
      start_date: 5.days.ago,
      end_time: 4.days.ago,
      current_price: 1.0,
      status: :inactive
    )

    admin = create_actor(role: :admin)
    get "/api/v1/admin/auctions", headers: auth_headers_for(admin)
    assert_response :success

    body = JSON.parse(response.body)
    auctions = body["auctions"] || body["adminAuctions"] || body["admin_auctions"] || body
    auctions = auctions["auctions"] if auctions.is_a?(Hash) && auctions.key?("auctions")
    statuses = auctions.map { |auction| auction.fetch("status") }

    assert_includes statuses, "active"
    assert_includes statuses, "scheduled"
    assert_includes statuses, "complete"
    assert_includes statuses, "cancelled"
    assert_includes statuses, "inactive"
    assert_includes auctions.map { |auction| auction.fetch("id") }, pending.id
    assert_includes auctions.map { |auction| auction.fetch("id") }, ended.id
    assert_includes auctions.map { |auction| auction.fetch("id") }, cancelled.id
    assert_includes auctions.map { |auction| auction.fetch("id") }, inactive.id
  end

  test "GET /api/v1/admin/auctions filters by storefront key" do
    main = Auction.create!(
      title: "Main Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "main",
      is_marketplace: false
    )
    marketplace = Auction.create!(
      title: "Marketplace Auction",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "marketplace",
      is_marketplace: true
    )

    admin = create_actor(role: :admin)
    get "/api/v1/admin/auctions", params: { storefront_key: "marketplace" }, headers: auth_headers_for(admin)
    assert_response :success

    body = JSON.parse(response.body)
    auctions = body["auctions"] || body["adminAuctions"] || body["admin_auctions"] || body
    auctions = auctions["auctions"] if auctions.is_a?(Hash) && auctions.key?("auctions")
    ids = auctions.map { |auction| auction.fetch("id") }

    assert_includes ids, marketplace.id
    refute_includes ids, main.id
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

  test "POST /api/v1/admin/auctions enforces role matrix and creates auctions" do
    payload = {
      auction: {
        title: "Namespace Auction",
        description: "Desc",
        start_date: Time.current.iso8601,
        end_time: 1.day.from_now.iso8601,
        current_price: 10.0,
        status: "scheduled"
      }
    }

    each_role_case(required_role: :admin, success_status: 201) do |role:, headers:, expected_status:, success:, **|
      assert_difference("Auction.count", success ? 1 : 0, "role=#{role}") do
        post "/api/v1/admin/auctions", params: payload, headers: headers
      end

      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal "scheduled", body["status"]
      assert_equal "Namespace Auction", body["title"]
      assert body["id"].present?
    end
  end

  test "PUT /api/v1/admin/auctions/:id enforces role matrix and updates auctions" do
    auction = Auction.create!(
      title: "Update Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/admin/auctions/#{auction.id}", params: { auction: { title: "Updated Title" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "Updated Title", JSON.parse(response.body).fetch("title")
        assert_equal "Updated Title", auction.reload.title
      else
        assert_equal "Update Me", auction.reload.title
      end
    end
  end

  test "PUT /api/v1/admin/auctions/:id can update storefront assignment" do
    auction = Auction.create!(
      title: "Storefront Update",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :pending,
      storefront_key: "main",
      is_marketplace: false
    )

    admin = create_actor(role: :admin)
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "marketplace" } },
        headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "marketplace", body.fetch("storefront_key")
    assert_equal true, body.fetch("is_marketplace")

    auction.reload
    assert_equal "marketplace", auction.storefront_key
    assert_equal true, auction.is_marketplace
    assert_equal false, auction.is_adult
  end

  test "PUT /api/v1/admin/auctions/:id returns 422 for invalid storefront_key" do
    auction = Auction.create!(
      title: "Storefront Update Invalid",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :pending,
      storefront_key: "main",
      is_marketplace: false
    )

    admin = create_actor(role: :admin)
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "invalid-storefront" } },
        headers: auth_headers_for(admin)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_auction", body.dig("error", "code")
    assert_includes body.dig("error", "message"), "Storefront key must be one of"
    assert_includes body.dig("error", "field_errors", "storefront_key"), "must be one of: main, afterdark, marketplace"

    auction.reload
    assert_equal "main", auction.storefront_key
    assert_equal false, auction.is_marketplace
  end

  test "PUT /api/v1/admin/auctions/:id storefront_key takes precedence over legacy flags" do
    auction = Auction.create!(
      title: "Storefront Precedence",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :pending,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )

    admin = create_actor(role: :admin)
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "marketplace", is_adult: true, is_marketplace: false } },
        headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "marketplace", body.fetch("storefront_key")
    assert_equal true, body.fetch("is_marketplace")
    assert_equal false, body.fetch("is_adult")

    auction.reload
    assert_equal "marketplace", auction.storefront_key
    assert_equal true, auction.is_marketplace
    assert_equal false, auction.is_adult
  end

  test "PUT /api/v1/admin/auctions/:id returns 422 when storefront reassignment conflicts with existing bids" do
    auction = Auction.create!(
      title: "Storefront Bid Conflict",
      description: "Desc",
      start_date: 1.hour.ago,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )
    bidder = create_actor(role: :user)
    Bid.create!(auction: auction, user: bidder, amount: 2.0, storefront_key: "main")

    admin = create_actor(role: :admin)
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "marketplace" } },
        headers: auth_headers_for(admin)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_auction", body.dig("error", "code")
    assert_includes body.dig("error", "field_errors", "storefront_key"), "cannot be reassigned after bids have been placed"

    auction.reload
    assert_equal "main", auction.storefront_key
    assert_equal false, auction.is_marketplace
  end

  test "PUT /api/v1/admin/auctions/:id storefront reassignment preserves status and non-storefront fields" do
    auction = Auction.create!(
      title: "Preserve Fields",
      description: "Original description",
      start_date: Time.current,
      end_time: 2.hours.from_now,
      current_price: 13.5,
      status: :pending,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )

    admin = create_actor(role: :admin)
    put "/api/v1/admin/auctions/#{auction.id}",
        params: { auction: { storefront_key: "afterdark" } },
        headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "afterdark", body.fetch("storefront_key")
    assert_equal false, body.fetch("is_marketplace")
    assert_equal true, body.fetch("is_adult")
    assert_equal "scheduled", body.fetch("status")
    assert_equal "Preserve Fields", body.fetch("title")
    assert_equal "Original description", body.fetch("description")
    assert_equal "13.5", body.fetch("current_price")

    auction.reload
    assert_equal "pending", auction.status
    assert_equal "Preserve Fields", auction.title
    assert_equal "Original description", auction.description
    assert_equal BigDecimal("13.5"), auction.current_price
  end

  test "PUT /api/v1/admin/auctions/:id restores inactive auction when status is scheduled" do
    auction = Auction.create!(
      title: "Restore Me",
      description: "Desc",
      start_date: 2.hours.from_now,
      end_time: 3.hours.from_now,
      current_price: 1.0,
      status: :inactive
    )

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/admin/auctions/#{auction.id}", params: { auction: { status: "scheduled" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "scheduled", body.fetch("status")
        assert_equal "pending", auction.reload.status
      else
        assert_equal "inactive", auction.reload.status
      end
    end
  end

  test "PUT /api/v1/admin/auctions/:id transitions scheduled auction to active" do
    auction = Auction.create!(
      title: "Schedule Then Activate",
      description: "Desc",
      start_date: 2.hours.from_now,
      end_time: 3.hours.from_now,
      current_price: 1.0,
      status: :pending
    )

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/admin/auctions/#{auction.id}", params: { auction: { status: "active" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "active", body.fetch("status")
        assert_equal "active", auction.reload.status
      else
        assert_equal "pending", auction.reload.status
      end
    end
  end

  test "PUT /api/v1/admin/auctions/:id transitions active auction to complete" do
    auction = Auction.create!(
      title: "Complete Me",
      description: "Desc",
      start_date: 2.hours.ago,
      end_time: 1.minute.ago,
      current_price: 1.0,
      status: :active
    )

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/admin/auctions/#{auction.id}", params: { auction: { status: "complete" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "complete", body.fetch("status")
        assert_equal "ended", auction.reload.status
      else
        assert_equal "active", auction.reload.status
      end
    end
  end

  test "PUT /api/v1/admin/auctions/:id rejects inactive to active transition" do
    auction = Auction.create!(
      title: "Cannot Publish",
      description: "Desc",
      start_date: 2.hours.from_now,
      end_time: 3.hours.from_now,
      current_price: 1.0,
      status: :inactive
    )

    each_role_case(required_role: :admin, success_status: 422) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/admin/auctions/#{auction.id}", params: { auction: { status: "active" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "invalid_state", body.dig("error", "code").to_s
        assert_match "inactive to active", body.dig("error", "message")
        assert_equal "inactive", auction.reload.status
      else
        assert_equal "inactive", auction.reload.status
      end
    end
  end

  test "DELETE /api/v1/admin/auctions/:id enforces role matrix and retires auctions" do
    each_role_case(required_role: :admin, success_status: 204) do |role:, headers:, expected_status:, success:, **|
      auction = Auction.create!(
        title: "Retire Cleanly",
        description: "Desc",
        start_date: Time.current,
        end_time: 1.hour.from_now,
        current_price: 1.0,
        status: :active
      )

      delete "/api/v1/admin/auctions/#{auction.id}", headers: headers

      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "inactive", auction.reload.status
      else
        assert_equal "active", auction.reload.status
      end
    end
  end

  test "POST /api/v1/admin/auctions/:id/extend_time enforces role matrix and extends auctions" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      auction = Auction.create!(
        title: "Extendable Auction",
        description: "Desc",
        start_date: Time.current,
        end_time: 10.seconds.from_now,
        current_price: 1.0,
        status: :active
      )
      original_end_time = auction.end_time

      post "/api/v1/admin/auctions/#{auction.id}/extend_time", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      new_end_time = Time.iso8601(body.fetch("end_time"))
      assert new_end_time > original_end_time
      assert auction.reload.end_time > original_end_time
    end
  end
end
