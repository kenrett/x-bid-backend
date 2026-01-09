require "test_helper"

class StorefrontKeyAttributionTest < ActionDispatch::IntegrationTest
  test "afterdark request persists storefront_key on bid, money_event, and credit_transaction" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)

    auction = Auction.create!(
      title: "Afterdark Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: BigDecimal("1.00"),
      status: :active,
      storefront_key: "afterdark"
    )

    Credits::Apply.apply!(
      user: user,
      reason: "seed_grant",
      amount: 1,
      idempotency_key: "test:storefront_key_attribution:seed:#{user.id}",
      storefront_key: "afterdark"
    )

    host!("afterdark.biddersweet.app")
    post "/api/v1/auctions/#{auction.id}/bids", headers: auth_headers_for(user)
    assert_response :success

    bid = auction.bids.order(created_at: :desc).first
    assert bid.present?
    assert_equal "afterdark", bid.storefront_key

    credit_tx = CreditTransaction.where(user: user, auction: auction, reason: "bid_placed").order(created_at: :desc).first
    assert credit_tx.present?
    assert_equal "afterdark", credit_tx.storefront_key

    money_event = MoneyEvent.where(user: user, event_type: "bid_spent", source_type: "Bid", source_id: bid.id.to_s).order(created_at: :desc).first
    assert money_event.present?
    assert_equal "afterdark", money_event.storefront_key

    audit_log = AuditLog.where(action: "auction.bid.placed", user_id: user.id).order(created_at: :desc).first
    assert audit_log.present?
    assert_equal "afterdark", audit_log.storefront_key
  end

  test "background writes default storefront_key to main with warning" do
    Current.reset

    warnings = []
    Rails.logger.stub(:warn, ->(msg) { warnings << msg }) do
      auction = Auction.create!(
        title: "Background Auction",
        description: "Desc",
        start_date: 1.minute.ago,
        end_time: 1.hour.from_now,
        current_price: BigDecimal("1.00"),
        status: :active
      )

      assert_equal "main", auction.storefront_key
    end

    assert warnings.any? { |msg| msg.to_s.include?("storefront_key.defaulted") }
  end
end
