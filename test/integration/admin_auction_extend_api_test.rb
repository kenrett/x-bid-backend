require "test_helper"

class AdminAuctionExtendApiTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/auctions/:id/extend_time enforces role matrix and extends within window" do
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

      post "/api/v1/auctions/#{auction.id}/extend_time", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      new_end_time = Time.iso8601(body.fetch("end_time"))
      assert new_end_time > original_end_time
      assert auction.reload.end_time > original_end_time
    end
  end

  test "returns invalid_state when auction is outside the extend window" do
    each_role_case(required_role: :admin, success_status: 422) do |role:, headers:, expected_status:, success:, **|
      auction = Auction.create!(
        title: "Too Far Out",
        description: "Desc",
        start_date: Time.current,
        end_time: 1.hour.from_now,
        current_price: 1.0,
        status: :active
      )
      original_end_time = auction.end_time

      post "/api/v1/auctions/#{auction.id}/extend_time", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal "invalid_state", body["error_code"]
      assert_equal original_end_time.to_i, auction.reload.end_time.to_i
    end
  end

  test "returns not_found for missing auction" do
    each_role_case(required_role: :admin, success_status: 404) do |role:, headers:, expected_status:, success:, **|
      post "/api/v1/auctions/999999/extend_time", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal "not_found", body["error_code"]
    end
  end
end
