require "test_helper"
require "stringio"

class CreditsApplyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "apply@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "apply is idempotent by key and keeps cached balance correct" do
    key = "apply-1"

    Credits::Apply.apply!(user: @user, reason: "bonus", amount: 5, idempotency_key: key)
    Credits::Apply.apply!(user: @user, reason: "bonus", amount: 5, idempotency_key: key)

    assert_equal 1, CreditTransaction.where(idempotency_key: key).count
    assert_equal 5, Credits::Balance.for_user(@user)
    assert_equal 5, @user.reload.bid_credits
  end

  test "violations are observable in logs when granting purchase credits without a purchase" do
    io = StringIO.new
    logger = Logger.new(io)

    Rails.stub(:logger, logger) do
      error = assert_raises(ArgumentError) do
        Credits::Apply.apply!(
          user: @user,
          reason: "bid_pack_purchase",
          amount: 5,
          idempotency_key: "bad-grant",
          purchase: nil,
          stripe_payment_intent_id: "pi_missing"
        )
      end

      assert_match(/require a purchase/, error.message)
    end

    output = io.string
    assert_includes output, "\"event\":\"credits.grant_without_purchase\""
    assert_includes output, "\"stripe_payment_intent_id\":\"pi_missing\""
    assert_equal 0, @user.reload.bid_credits
  end

  test "concurrent grants do not lose updates" do
    keys = %w[apply-concurrent-1 apply-concurrent-2]
    gate = Queue.new

    threads =
      keys.map do |key|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            gate.pop
            Credits::Apply.apply!(
              user: @user,
              reason: "bonus",
              amount: 3,
              idempotency_key: key
            )
          end
        end
      end

    2.times { gate << true }
    threads.each(&:join)

    assert_equal 2, CreditTransaction.where(idempotency_key: keys).count
    assert_equal 6, @user.reload.bid_credits
  end
end
