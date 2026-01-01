require "test_helper"

class AdminAuctionsApiTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/auctions enforces role matrix and creates auctions" do
    payload = {
      auction: {
        title: "Test Auction",
        description: "Desc",
        start_date: Time.current.iso8601,
        end_time: 1.day.from_now.iso8601,
        current_price: 10.0,
        status: "scheduled"
      }
    }

    each_role_case(required_role: :admin, success_status: 201) do |role:, headers:, expected_status:, success:, **|
      assert_difference("Auction.count", success ? 1 : 0, "role=#{role}") do
        post "/api/v1/auctions", params: payload, headers: headers
      end

      assert_response expected_status

      next unless success

      body = JSON.parse(response.body)
      assert_equal "scheduled", body["status"]
      assert_equal "Test Auction", body["title"]
      assert body["id"].present?
    end
  end

  test "rejects retiring auction with bids" do
    auction = Auction.create!(
      title: "Retire Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )
    bidder = User.create!(
      name: "Bidder",
      email_address: "bidder@example.com",
      password: "password",
      bid_credits: 0
    )
    Bid.create!(user: bidder, auction: auction, amount: 2.0)

    each_role_case(required_role: :admin, success_status: 422) do |role:, headers:, expected_status:, success:, **|
      delete "/api/v1/auctions/#{auction.id}", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_includes body.dig("error", "message"), "Cannot retire an auction that has bids"
    end
  end

  test "retires auction without bids and returns no content" do
    each_role_case(required_role: :admin, success_status: 204) do |role:, headers:, expected_status:, success:, **|
      auction = Auction.create!(
        title: "Retire Cleanly",
        description: "Desc",
        start_date: Time.current,
        end_time: 1.hour.from_now,
        current_price: 1.0,
        status: :active
      )

      delete "/api/v1/auctions/#{auction.id}", headers: headers

      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "inactive", auction.reload.status
      else
        assert_equal "active", auction.reload.status
      end
    end
  end

  test "returns an error when retiring an already inactive auction" do
    auction = Auction.create!(
      title: "Already Inactive",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    admin = create_actor(role: :admin)
    delete "/api/v1/auctions/#{auction.id}", headers: auth_headers_for(admin)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "Auction already inactive", body.dig("error", "message")
  end

  test "PUT /api/v1/auctions/:id enforces role matrix and updates auctions" do
    auction = Auction.create!(
      title: "Update Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/auctions/#{auction.id}", params: { auction: { title: "Updated Title" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      if success
        assert_equal "Updated Title", JSON.parse(response.body).fetch("title")
        assert_equal "Updated Title", auction.reload.title
      else
        assert_equal "Update Me", auction.reload.title
      end
    end
  end

  test "invalid status returns 422" do
    auction = Auction.create!(
      title: "Update Me",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :inactive
    )

    each_role_case(required_role: :admin, success_status: 422) do |role:, headers:, expected_status:, success:, **|
      put "/api/v1/auctions/#{auction.id}", params: { auction: { status: "not-a-status" } }, headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_includes body.dig("error", "message"), "Invalid status"
    end
  end

  test "blocks hard delete through the model" do
    auction = Auction.create!(
      title: "Do Not Delete",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )

    assert_no_difference("Auction.count") do
      assert_not auction.destroy
    end

    assert_includes auction.errors.full_messages, "Auctions cannot be hard-deleted; retire instead"
    assert_equal "active", auction.reload.status
  end
end
