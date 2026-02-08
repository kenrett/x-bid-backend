require "test_helper"

class AdminPaymentsApiTest < ActionDispatch::IntegrationTest
  def setup
    @bid_pack = BidPack.create!(
      name: "Starter",
      bids: 10,
      price: BigDecimal("9.99"),
      highlight: false,
      description: "test pack",
      active: true
    )
  end

  test "GET /api/v1/admin/payments enforces role matrix" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/payments", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      payments = body.fetch("payments")
      assert_kind_of Array, payments
      assert_equal purchase.id, payments.first["id"]
      assert_equal user.email_address, payments.first["user_email"]
    end
  end

  test "GET /api/v1/admin/payments/:id enforces role matrix" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      get "/api/v1/admin/payments/#{purchase.id}", headers: headers
      assert_response expected_status, "role=#{role}"

      next unless success

      body = JSON.parse(response.body)
      assert_equal purchase.id, body.dig("purchase", "id")
      assert_kind_of Array, body["credit_transactions"]
      assert body.key?("balance_audit")
    end
  end

  test "returns payments for admins" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    admin = create_actor(role: :admin)
    get "/api/v1/admin/payments", headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    payment = body.fetch("payments").find { |p| p["id"] == purchase.id }
    assert payment, "Expected payments list to include purchase id=#{purchase.id}"
    assert_equal purchase.id, payment["id"]
    assert_equal user.email_address, payment["user_email"]
    assert_in_delta @bid_pack.price.to_f, payment["amount"].to_f, 0.001
    assert_equal purchase.status, payment["status"]
    assert payment["created_at"].present?
    assert_equal purchase.stripe_checkout_session_id, payment["stripe_checkout_session_id"]
    assert_equal purchase.stripe_payment_intent_id, payment["stripe_payment_intent_id"]
    assert_nil payment["stripe_event_id"]
  end

  test "filters payments by user email search" do
    matching_user = create_user(email: "match@example.com")
    other_user = create_user(email: "other@example.com")
    create_purchase(user: matching_user)
    create_purchase(user: other_user)

    admin = create_actor(role: :admin)
    get "/api/v1/admin/payments", params: { search: "match" }, headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    payments = body.fetch("payments")
    assert_equal 1, payments.size
    assert_equal matching_user.email_address, payments.first["user_email"]
  end

  test "POST /api/v1/admin/payments/:id/refund enforces role matrix and updates payment" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, actor:, headers:, expected_status:, success:|
      user = create_user(email: "buyer-#{role}@example.com")
      purchase = create_purchase(user:)

      fake_service = Class.new do
        def initialize(payment)
          @payment = payment
        end

        def call
          @payment.update!(status: "refunded", refunded_cents: 500)
          ServiceResult.ok(code: :refunded, data: { refund_id: "re_fake" })
        end
      end

      captured_kwargs = nil
      Admin::Payments::IssueRefund.stub(:new, ->(**kwargs) { captured_kwargs = kwargs; fake_service.new(kwargs[:payment]) }) do
        post "/api/v1/admin/payments/#{purchase.id}/refund",
             params: { amount_cents: 500, reason: "mistake" },
             headers: headers
      end

      assert_response expected_status, "role=#{role}"

      if success
        body = JSON.parse(response.body)
        assert_equal "refunded", body["status"]
        assert_equal 500, body["refunded_cents"]
        assert_equal "re_fake", body["refund_id"]
        assert_equal actor, captured_kwargs[:actor]
        assert_equal purchase, captured_kwargs[:payment]
        assert_equal 500, captured_kwargs[:amount_cents]
        assert_equal false, captured_kwargs[:full_refund]
        assert_equal "mistake", captured_kwargs[:reason]
        assert_equal "refunded", purchase.reload.status
      else
        assert_nil captured_kwargs
        assert_equal "applied", purchase.reload.status
      end
    end
  end

  test "POST /api/v1/admin/payments/:id/refund rejects requests without amount_cents or full_refund=true" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    admin = create_actor(role: :admin)

    issue_refund = Class.new do
      def call
        raise "should not be called"
      end
    end

    Admin::Payments::IssueRefund.stub(:new, ->(**_) { issue_refund.new }) do
      post "/api/v1/admin/payments/#{purchase.id}/refund",
           params: { reason: "missing amount" },
           headers: auth_headers_for(admin)
    end

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_amount", body.dig("error", "code")
  end

  test "POST /api/v1/admin/payments/:id/refund accepts explicit full_refund=true without amount_cents" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    admin = create_actor(role: :admin)

    captured_kwargs = nil
    fake_service = Class.new do
      def call
        ServiceResult.ok(code: :refunded, data: { refund_id: "re_full" })
      end
    end

    Admin::Payments::IssueRefund.stub(:new, ->(**kwargs) { captured_kwargs = kwargs; fake_service.new }) do
      post "/api/v1/admin/payments/#{purchase.id}/refund",
           params: { full_refund: true, reason: "admin_full_refund" },
           headers: auth_headers_for(admin)
    end

    assert_response :success
    assert_equal purchase, captured_kwargs[:payment]
    assert_nil captured_kwargs[:amount_cents]
    assert_equal true, captured_kwargs[:full_refund]
    assert_equal "admin_full_refund", captured_kwargs[:reason]
  end

  test "POST /api/v1/admin/payments/:id/repair_credits enforces role matrix and repairs ledger" do
    each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:, **|
      user = create_user(email: "buyer-repair-#{role}@example.com")
      purchase = create_purchase(user:)

      assert_difference("CreditTransaction.count", success ? 1 : 0, "role=#{role}") do
        post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: headers
      end

      assert_response expected_status

      if success
        body = JSON.parse(response.body)
        assert_equal purchase.id, body.dig("purchase", "id")
        assert_kind_of Array, body["credit_transactions"]
        assert_equal 1, body["credit_transactions"].size
      else
        assert_equal 0, CreditTransaction.where(purchase_id: purchase.id).count
      end
    end
  end

  test "shows payment reconciliation with matching ledger entry" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    credit = CreditTransaction.create!(
      user: user,
      purchase: purchase,
      kind: :grant,
      amount: @bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      metadata: {}
    )
    Credits::RebuildBalance.call!(user: user)

    admin = create_actor(role: :admin)
    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal user.email_address, body.dig("purchase", "user_email")
    assert_equal purchase.amount_cents, body.dig("purchase", "amount_cents")
    assert_equal purchase.currency, body.dig("purchase", "currency")
    assert_equal purchase.status, body.dig("purchase", "status")
    assert_equal purchase.stripe_payment_intent_id, body.dig("purchase", "stripe_payment_intent_id")

    txs = body["credit_transactions"]
    assert_equal 1, txs.size
    assert_equal credit.id, txs.first["id"]
    assert_equal "grant", txs.first["kind"]
    assert_equal @bid_pack.bids, txs.first["amount"]
    assert_equal "purchase:#{purchase.id}:grant", txs.first["idempotency_key"]

    audit = body["balance_audit"]
    assert_equal true, audit["matches"]
    assert_equal user.reload.bid_credits, audit["cached"]
    assert_equal user.reload.bid_credits, audit["derived"]
  end

  test "shows empty credit transaction list when ledger entry missing" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    admin = create_actor(role: :admin)
    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal [], body["credit_transactions"]
  end

  test "balance audit mismatch surfaces correctly" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)
    CreditTransaction.create!(
      user: user,
      purchase: purchase,
      kind: :grant,
      amount: @bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      metadata: {}
    )
    Credits::RebuildBalance.call!(user: user)
    user.update_columns(bid_credits: user.bid_credits + 1)

    admin = create_actor(role: :admin)
    get "/api/v1/admin/payments/#{purchase.id}", headers: auth_headers_for(admin)

    assert_response :success
    audit = JSON.parse(response.body)["balance_audit"]
    assert_equal false, audit["matches"]
    assert_equal user.reload.bid_credits, audit["cached"]
    assert_equal Credits::Balance.derived_for_user(user), audit["derived"]
  end

  test "repair_credits creates missing ledger row and returns reconciliation view" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    assert_equal 0, CreditTransaction.where(purchase_id: purchase.id).count

    admin = create_actor(role: :admin)
    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers_for(admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["idempotent"]
    assert_equal purchase.id, body.dig("purchase", "id")
    assert_equal 1, body["credit_transactions"].size
    assert_equal true, body.dig("balance_audit", "matches")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  test "repair_credits is safe to call twice" do
    user = create_user(email: "buyer@example.com")
    purchase = create_purchase(user:)

    admin = create_actor(role: :admin)
    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers_for(admin)
    assert_response :success
    body1 = JSON.parse(response.body)
    assert_equal false, body1["idempotent"]

    post "/api/v1/admin/payments/#{purchase.id}/repair_credits", headers: auth_headers_for(admin)
    assert_response :success
    body2 = JSON.parse(response.body)
    assert_equal true, body2["idempotent"]

    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
  end

  private

  def create_user(email:, role: :user)
    User.create!(
      name: "User",
      email_address: email,
      password: "password",
      role: role,
      bid_credits: 0
    )
  end

  def create_purchase(user:)
    Purchase.create!(
      user: user,
      bid_pack: @bid_pack,
      amount_cents: (@bid_pack.price * 100).to_i,
      currency: "usd",
      stripe_checkout_session_id: SecureRandom.uuid,
      stripe_payment_intent_id: SecureRandom.uuid,
      status: "applied"
    )
  end
end
