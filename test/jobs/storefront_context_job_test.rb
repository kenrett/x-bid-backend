require "test_helper"
require "securerandom"

class StorefrontContextLedgerJob < ApplicationJob
  queue_as :default

  cattr_accessor :last_current_storefront

  def perform(user_id:, storefront_key:, idempotency_key:)
    with_storefront_context(storefront_key: storefront_key) do
      self.class.last_current_storefront = Current.storefront_key
      Credits::Ledger::Writer.write!(
        user: User.find(user_id),
        kind: :grant,
        amount: 1,
        reason: "job.test",
        idempotency_key: idempotency_key,
        metadata: { job: "storefront_context" }
      )
    end
  end
end

class StorefrontContextJobTest < ActiveSupport::TestCase
  setup do
    Current.reset
    StorefrontContextLedgerJob.last_current_storefront = nil
    CreditTransaction.delete_all
  end

  teardown do
    Current.reset
    StorefrontContextLedgerJob.last_current_storefront = nil
    CreditTransaction.delete_all
  end

  test "job honors storefront_key provided from caller" do
    user = create_actor(role: :user)
    key = "afterdark"

    StorefrontContextLedgerJob.perform_now(
      user_id: user.id,
      storefront_key: key,
      idempotency_key: "job:test:#{SecureRandom.hex(6)}"
    )

    assert_equal key, StorefrontContextLedgerJob.last_current_storefront
    assert_equal key, CreditTransaction.last.storefront_key
  end

  test "invalid storefront_key logs warning and defaults to main" do
    user = create_actor(role: :user)
    logs = []

    AppLogger.stub(:log, ->(**context) { logs << context; nil }) do
      StorefrontContextLedgerJob.perform_now(
        user_id: user.id,
        storefront_key: "bogus",
        idempotency_key: "job:test:#{SecureRandom.hex(6)}"
      )
    end

    assert_equal "main", StorefrontContextLedgerJob.last_current_storefront
    assert_equal "main", CreditTransaction.last.storefront_key
    assert logs.any? { |h| h[:event] == "jobs.storefront.invalid_key" }
  end
end
