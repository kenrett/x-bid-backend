require "test_helper"

class ObservabilityLoggingTest < ActionDispatch::IntegrationTest
  FakeCheckoutCreateSession = Struct.new(:id, :client_secret, keyword_init: true)

  test "checkout create emits structured logs with request and session context" do
    user = create_actor(role: :user)
    user.update!(email_verified_at: Time.current)

    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )

    bid_pack = BidPack.create!(name: "Log Pack", bids: 10, price: BigDecimal("9.99"), highlight: false, description: "test", active: true)

    captured = []
    logger = Rails.logger
    capture_json = lambda do |*args, &block|
      msg = args.first
      msg = block.call if msg.nil? && block
      return if msg.nil?

      parsed = JSON.parse(msg.to_s)
      captured << parsed if parsed.is_a?(Hash) && parsed["event"].present?
    rescue JSON::ParserError
      nil
    end

    Stripe::Checkout::Session.stub(:create, ->(_attrs) { FakeCheckoutCreateSession.new(id: "cs_log", client_secret: "cs_secret_log") }) do
      logger.stub(:info, capture_json) do
        post "/api/v1/checkouts", params: { bid_pack_id: bid_pack.id }, headers: auth_headers(user, session_token)
      end
    end

    assert_response :success

    started = captured.find { |e| e["event"] == "checkout.create.started" }
    succeeded = captured.find { |e| e["event"] == "checkout.create.succeeded" }
    assert started, "Expected checkout.create.started log event"
    assert succeeded, "Expected checkout.create.succeeded log event"

    [ started, succeeded ].each do |entry|
      assert entry["request_id"].present?
      assert_equal user.id, entry["user_id"]
      assert_equal session_token.id, entry["session_token_id"]
    end

    assert_equal bid_pack.id, started["bid_pack_id"]
    assert_equal bid_pack.id, succeeded["bid_pack_id"]
    assert_equal "cs_log", succeeded["stripe_checkout_session_id"]
  end

  private

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
