require "test_helper"

class AdminFulfillmentsApiTest < ActionDispatch::IntegrationTest
  def setup
    @winner = create_actor(role: :user)
  end

  test "POST /api/v1/admin/fulfillments/:id/process enforces role matrix and updates fulfillment" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      fulfillment = create_fulfillment!(status: :claimed)

      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        post "/api/v1/admin/fulfillments/#{fulfillment.id}/process",
             params: { shipping_cost_cents: 500, notes: "pack carefully" },
             headers: headers
      end

      assert_response expected_status

      if success
        body = JSON.parse(response.body)
        assert_equal "processing", body.fetch("status")
        assert_equal 500, body.fetch("shipping_cost_cents")
        assert_equal "pack carefully", body.dig("metadata", "admin_notes", "processing")
        assert_equal "processing", fulfillment.reload.status

        log = AuditLog.where(action: "fulfillment.process").order(created_at: :desc).first
        assert_equal "fulfillment.process", log.action
        assert_equal actor.id, log.actor_id
        assert_equal fulfillment.id, log.target_id
      else
        assert_equal "claimed", fulfillment.reload.status
      end
    end
  end

  test "POST /api/v1/admin/fulfillments/:id/ship enforces role matrix and updates fulfillment" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      fulfillment = create_fulfillment!(status: :processing)

      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        post "/api/v1/admin/fulfillments/#{fulfillment.id}/ship",
             params: { shipping_carrier: "ups", tracking_number: "1Z999" },
             headers: headers
      end

      assert_response expected_status

      if success
        body = JSON.parse(response.body)
        assert_equal "shipped", body.fetch("status")
        assert_equal "ups", body.fetch("shipping_carrier")
        assert_equal "1Z999", body.fetch("tracking_number")
        assert_equal "shipped", fulfillment.reload.status

        log = AuditLog.where(action: "fulfillment.ship").order(created_at: :desc).first
        assert_equal "fulfillment.ship", log.action
        assert_equal actor.id, log.actor_id
        assert_equal fulfillment.id, log.target_id
      else
        assert_equal "processing", fulfillment.reload.status
      end
    end
  end

  test "POST /api/v1/admin/fulfillments/:id/complete enforces role matrix and updates fulfillment" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      fulfillment = create_fulfillment!(status: :shipped)

      assert_difference("AuditLog.count", success ? 2 : 0, "role=#{role}") do
        post "/api/v1/admin/fulfillments/#{fulfillment.id}/complete", headers: headers
      end

      assert_response expected_status

      if success
        assert_equal "complete", JSON.parse(response.body).fetch("status")
        assert_equal "complete", fulfillment.reload.status

        log = AuditLog.where(action: "fulfillment.complete").order(created_at: :desc).first
        assert_equal "fulfillment.complete", log.action
        assert_equal actor.id, log.actor_id
        assert_equal fulfillment.id, log.target_id
      else
        assert_equal "shipped", fulfillment.reload.status
      end
    end
  end

  private

  def create_fulfillment!(status:)
    auction = Auction.create!(
      title: "Win",
      description: "desc",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: BigDecimal("9.00"),
      status: :ended,
      winning_user: @winner
    )
    bid = Bid.create!(user: @winner, auction: auction, amount: BigDecimal("10.00"))
    settlement = AuctionSettlement.create!(
      auction: auction,
      winning_user: @winner,
      winning_bid: bid,
      final_price: BigDecimal("10.00"),
      currency: "usd",
      status: :paid,
      ended_at: 2.days.ago
    )
    fulfillment = AuctionFulfillment.create!(auction_settlement: settlement, user: @winner)

    case status.to_sym
    when :pending
      # no-op
    when :claimed
      fulfillment.transition_to!(:claimed)
    when :processing
      fulfillment.transition_to!(:claimed)
      fulfillment.transition_to!(:processing)
    when :shipped
      fulfillment.transition_to!(:claimed)
      fulfillment.transition_to!(:processing)
      fulfillment.transition_to!(:shipped)
    else
      raise ArgumentError, "Unsupported fulfillment status: #{status.inspect}"
    end

    fulfillment
  end
end
