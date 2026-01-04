require "test_helper"

class IdorUserScopedEndpointsTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/me/purchases/:id does not allow cross-user access" do
    user_a = create_actor(role: :user)
    user_b = create_actor(role: :user)

    bid_pack = BidPack.create!(name: "Pack", description: "Desc", bids: 10, price: 1.0, active: true)
    purchase_b = Purchase.create!(
      user: user_b,
      bid_pack: bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_payment_intent_id: "pi_idor_#{SecureRandom.hex(4)}",
      status: "completed"
    )
    CreditTransaction.create!(
      user: user_b,
      purchase: purchase_b,
      kind: :grant,
      amount: bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase_b.id}:grant",
      metadata: {}
    )

    get "/api/v1/me/purchases/#{purchase_b.id}", headers: auth_headers_for(user_a)
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s

    get "/api/v1/me/purchases/#{purchase_b.id}", headers: auth_headers_for(user_b)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal purchase_b.id, body.fetch("id")
  end

  test "DELETE /api/v1/account/sessions/:id does not allow cross-user revocation" do
    user_a = create_actor(role: :user)
    user_b = create_actor(role: :user)

    user_b_current_headers = auth_headers_for(user_b)
    user_b_other_token = SessionToken.create!(
      user: user_b,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )

    delete "/api/v1/account/sessions/#{user_b_other_token.id}", headers: auth_headers_for(user_a)
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code").to_s
    refute user_b_other_token.reload.revoked_at?, "Expected token to remain active"

    delete "/api/v1/account/sessions/#{user_b_other_token.id}", headers: user_b_current_headers
    assert_response :success
    assert user_b_other_token.reload.revoked_at?, "Expected token to be revoked by owner"
  end

  test "DELETE /api/v1/auctions/:id/watch cannot remove another user's watch" do
    user_a = create_actor(role: :user)
    user_b = create_actor(role: :user)
    auction = Auction.create!(
      title: "A",
      description: "Desc",
      start_date: 1.hour.ago,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active
    )

    AuctionWatch.create!(user: user_b, auction: auction)
    assert_equal 1, AuctionWatch.where(user_id: user_b.id, auction_id: auction.id).count

    delete "/api/v1/auctions/#{auction.id}/watch", headers: auth_headers_for(user_a)
    assert_response :no_content

    assert_equal 1, AuctionWatch.where(user_id: user_b.id, auction_id: auction.id).count
  end

  test "admin-only endpoints remain admin-only" do
    user = create_actor(role: :user)

    get "/api/v1/admin/payments", headers: auth_headers_for(user)

    assert_forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body.dig("error", "code").to_s
  end
end
