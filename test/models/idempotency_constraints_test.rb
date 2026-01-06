require "test_helper"

class IdempotencyConstraintsTest < ActiveSupport::TestCase
  test "Stripe event, purchase, and credit idempotency constraints exist" do
    conn = ActiveRecord::Base.connection

    stripe_event_index = conn.indexes(:stripe_events).find { |i| i.unique && i.columns == [ "stripe_event_id" ] }
    assert stripe_event_index, "Expected unique index on stripe_events.stripe_event_id"

    purchase_indexes = conn.indexes(:purchases)
    assert purchase_indexes.any? { |i| i.unique && i.columns == [ "stripe_payment_intent_id" ] }, "Expected unique index on purchases.stripe_payment_intent_id"
    assert purchase_indexes.any? { |i| i.unique && i.columns == [ "stripe_checkout_session_id" ] }, "Expected unique index on purchases.stripe_checkout_session_id"

    credit_indexes = conn.indexes(:credit_transactions)
    assert credit_indexes.any? { |i| i.unique && i.columns == [ "idempotency_key" ] }, "Expected unique index on credit_transactions.idempotency_key"

    bpp_pi = credit_indexes.find { |i| i.name == "uniq_ct_bpp_grant_pi" }
    assert bpp_pi&.unique, "Expected uniq_ct_bpp_grant_pi to be unique"
    assert_includes bpp_pi.where.to_s, "reason", "Expected uniq_ct_bpp_grant_pi to be a partial index"

    bpp_cs = credit_indexes.find { |i| i.name == "uniq_ct_bpp_grant_cs" }
    assert bpp_cs&.unique, "Expected uniq_ct_bpp_grant_cs to be unique"
    assert_includes bpp_cs.where.to_s, "reason", "Expected uniq_ct_bpp_grant_cs to be a partial index"
  end
end
