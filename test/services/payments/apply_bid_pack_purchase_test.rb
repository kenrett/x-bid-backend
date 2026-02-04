require "test_helper"
require "ostruct"

class PaymentsApplyBidPackPurchaseTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(email_address: "buyer@example.com", password: "password", role: :user, bid_credits: 0)
    @bid_pack = BidPack.create!(name: "Starter", description: "Desc", bids: 100, price: 1.0, active: true)
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "happy path applies credits and completes purchase" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :available, "https://stripe.example/receipts/rcpt_1", "ch_1" ] }) do
      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_happy",
        stripe_payment_intent_id: "pi_happy",
        stripe_event_id: "evt_happy",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      assert result.ok?
      assert_equal false, result.idempotent
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_happy")
    assert_equal "applied", purchase.status
    assert_equal @bid_pack.id, purchase.bid_pack_id
    assert_equal 100, purchase.amount_cents
    assert_equal "usd", purchase.currency
    assert_equal "available", purchase.receipt_status
    assert_equal "https://stripe.example/receipts/rcpt_1", purchase.receipt_url
    assert_equal "ch_1", purchase.stripe_charge_id

    credit = CreditTransaction.find_by!(idempotency_key: "purchase:#{purchase.id}:grant")
    assert_equal "grant", credit.kind
    assert_equal @bid_pack.bids, credit.amount
    assert_equal @bid_pack.bids, @user.reload.bid_credits
  end

  test "logs payments.apply_purchase with user/bid_pack and stripe identifiers" do
    logs = []
    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      AppLogger.stub(:log, ->(**payload) { logs << payload }) do
        result = Payments::ApplyBidPackPurchase.call!(
          user: @user,
          bid_pack: @bid_pack,
          stripe_checkout_session_id: "cs_log",
          stripe_payment_intent_id: "pi_log",
          stripe_event_id: "evt_log",
          amount_cents: 100,
          currency: "usd",
          source: "test"
        )

        assert result.ok?
      end
    end

    apply_log = logs.find { |entry| entry[:event] == "payments.apply_purchase" }
    assert apply_log, "Expected payments.apply_purchase log"
    assert_equal @user.id, apply_log[:user_id]
    assert_equal @bid_pack.id, apply_log[:bid_pack_id]
    assert_equal "pi_log", apply_log[:stripe_payment_intent_id]
    assert_equal "cs_log", apply_log[:stripe_checkout_session_id]
    assert_equal "evt_log", apply_log[:stripe_event_id]
  end

  test "calling twice does not double-credit and creates purchase once" do
    result1 = nil
    assert_enqueued_jobs 1, only: PurchaseReceiptEmailJob do
      result1 = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_123",
        stripe_payment_intent_id: "pi_123",
        stripe_event_id: "evt_123",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )
    end
    assert_enqueued_with(
      job: PurchaseReceiptEmailJob,
      args: [ result1.purchase.id, { storefront_key: result1.purchase.storefront_key } ]
    )
    assert_equal 1, Notification.where(user: @user, kind: "purchase_completed").count

    result2 = nil
    assert_no_enqueued_jobs only: PurchaseReceiptEmailJob do
      result2 = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_123",
        stripe_payment_intent_id: "pi_123",
        stripe_event_id: "evt_123",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )
    end

    assert result1.ok?
    assert_equal false, result1.idempotent
    assert result2.ok?
    assert_equal true, result2.idempotent
    assert_equal 1, Notification.where(user: @user, kind: "purchase_completed").count

    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_123").count
    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_123")
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 100, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_123").count
    assert_equal "pending", purchase.receipt_status
  end

  test "writes a purchase money event for reconciliation" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(payment_intent_id:) { [ :pending, nil, nil ] }) do
      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_ledger",
        stripe_payment_intent_id: "pi_ledger",
        stripe_event_id: "evt_ledger",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      assert result.ok?
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_ledger")
    money_event = MoneyEvent.find_by!(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_ledger")
    assert_equal 100, money_event.amount_cents
    assert_equal "usd", money_event.currency
    assert_equal purchase.id, money_event.metadata["purchase_id"]
    assert_equal "evt_ledger", money_event.metadata["stripe_event_id"]
    assert_equal "cs_ledger", money_event.metadata["stripe_checkout_session_id"]
    assert_equal "test", money_event.metadata["source"]
  end

  test "repairs when purchase exists but credit grant is missing" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_payment_intent_id: "pi_456",
      status: "applied"
    )

    assert_equal 0, CreditTransaction.where(purchase_id: purchase.id).count

    result = nil
    assert_enqueued_jobs 1, only: PurchaseReceiptEmailJob do
      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: nil,
        stripe_payment_intent_id: "pi_456",
        stripe_event_id: nil,
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )
    end
    assert_enqueued_with(
      job: PurchaseReceiptEmailJob,
      args: [ result.purchase.id, { storefront_key: result.purchase.storefront_key } ]
    )
    assert_equal 1, Notification.where(user: @user, kind: "purchase_completed").count

    assert result.ok?
    assert_equal false, result.idempotent
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_456").count
    assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
    assert_equal 100, @user.reload.bid_credits
    assert_equal 1, MoneyEvent.where(event_type: :purchase, source_type: "StripePaymentIntent", source_id: "pi_456").count
    assert_equal "pending", Purchase.find_by!(stripe_payment_intent_id: "pi_456").receipt_status
  end

  test "reconciles missing ledger grant link without double-crediting" do
    purchase = Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_payment_intent_id: "pi_reconcile",
      status: "applied"
    )

    credit = CreditTransaction.create!(
      user: @user,
      kind: "grant",
      amount: @bid_pack.bids,
      reason: "bid_pack_purchase",
      idempotency_key: "purchase:#{purchase.id}:grant",
      purchase: purchase,
      storefront_key: "main"
    )

    assert_nil purchase.ledger_grant_credit_transaction_id

    result = nil
    assert_no_difference -> { CreditTransaction.count } do
      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: nil,
        stripe_payment_intent_id: "pi_reconcile",
        stripe_event_id: nil,
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )
    end

    assert result.ok?
    assert result.idempotent
    assert_equal credit.id, purchase.reload.ledger_grant_credit_transaction_id
  end

  test "duplicate deliveries with different stripe events stay idempotent" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(*) { [ :available, "https://stripe.example/receipts/dup", "ch_dup" ] }) do
      first = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_dup",
        stripe_payment_intent_id: "pi_dup",
        stripe_event_id: "evt_dup_1",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      second = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_dup",
        stripe_payment_intent_id: "pi_dup",
        stripe_event_id: "evt_dup_2",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      assert first.ok?
      assert second.ok?
      assert second.idempotent
      purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_dup")
      assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
      assert_equal 100, @user.reload.bid_credits
    end
  end

  test "out-of-order events still converge" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(*) { [ :available, "https://stripe.example/receipts/out", "ch_out" ] }) do
      later = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_out",
        stripe_payment_intent_id: "pi_out",
        stripe_event_id: "evt_out_later",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      earlier = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_out",
        stripe_payment_intent_id: "pi_out",
        stripe_event_id: "evt_out_earlier",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      assert later.ok?
      assert earlier.ok?
      assert earlier.idempotent
      assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_out").count
    end
  end

  test "partial failure then replay converges" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(*) { [ :available, "https://stripe.example/receipts/partial", "ch_partial" ] }) do
      applied = 0
      real_apply = Credits::Apply.method(:apply!)

      Credits::Apply.stub(:apply!, lambda { |**kwargs|
        applied += 1
        raise "boom" if applied == 1
        real_apply.call(**kwargs)
      }) do
        first_failed = Payments::ApplyBidPackPurchase.call!(
          user: @user,
          bid_pack: @bid_pack,
          stripe_checkout_session_id: "cs_partial",
          stripe_payment_intent_id: "pi_partial",
          stripe_event_id: "evt_partial",
          amount_cents: 100,
          currency: "usd",
          source: "test"
        )

        refute first_failed.ok?
      end

      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_partial",
        stripe_payment_intent_id: "pi_partial",
        stripe_event_id: "evt_partial",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      assert result.ok?
      assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_partial").count
      assert_equal 1, CreditTransaction.where(stripe_payment_intent_id: "pi_partial").count
    end
  end

  test "concurrent requests credit exactly once" do
    Payments::StripeReceiptLookup.stub(:lookup, ->(*) { [ :available, "https://stripe.example/receipts/conc", "ch_conc" ] }) do
      key = "evt_conc"
      threads = []

      2.times do
        threads << Thread.new do
          Payments::ApplyBidPackPurchase.call!(
            user: @user,
            bid_pack: @bid_pack,
            stripe_checkout_session_id: "cs_conc",
            stripe_payment_intent_id: "pi_conc",
            stripe_event_id: key,
            amount_cents: 100,
            currency: "usd",
            source: "test"
          )
        end
      end

      threads.each(&:join)

      purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_conc")
      assert_equal 1, CreditTransaction.where(idempotency_key: "purchase:#{purchase.id}:grant").count
      assert_equal 100, @user.reload.bid_credits
    end
  end

  test "partial failure does not apply state" do
    Credits::Apply.stub(:apply!, ->(**_) { raise "boom" }) do
      result = Payments::ApplyBidPackPurchase.call!(
        user: @user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_fail",
        stripe_payment_intent_id: "pi_fail",
        stripe_event_id: "evt_fail",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      refute result.ok?
      assert_equal :processing_error, result.code
    end

    assert_equal 0, Purchase.where(stripe_payment_intent_id: "pi_fail").count
    assert_equal 0, CreditTransaction.where(stripe_payment_intent_id: "pi_fail").count
    assert_equal 0, MoneyEvent.where(source_type: "StripePaymentIntent", source_id: "pi_fail").count
  end

  test "rejects attempts to apply a payment intent owned by a different user" do
    other_user = User.create!(email_address: "other@example.com", password: "password", role: :user, bid_credits: 0)

    Purchase.create!(
      user: @user,
      bid_pack: @bid_pack,
      amount_cents: 100,
      currency: "usd",
      stripe_payment_intent_id: "pi_shared",
      stripe_checkout_session_id: "cs_shared",
      status: "applied"
    )

    errors = []
    AppLogger.stub(:error, lambda { |event:, error:, **context|
      errors << { event: event, error_class: error.class.name, error_message: error.message, **context }
    }) do
      result = Payments::ApplyBidPackPurchase.call!(
        user: other_user,
        bid_pack: @bid_pack,
        stripe_checkout_session_id: "cs_shared",
        stripe_payment_intent_id: "pi_shared",
        stripe_event_id: "evt_shared",
        amount_cents: 100,
        currency: "usd",
        source: "test"
      )

      refute result.ok?
    end

    assert_equal 0, other_user.reload.bid_credits
    assert_equal 1, Purchase.where(stripe_payment_intent_id: "pi_shared").count
    error_log = errors.find { |e| e[:event] == "payments.apply_purchase.error" }
    assert error_log, "Expected payments.apply_purchase.error log"
    assert_equal other_user.id, error_log[:user_id]
    assert_equal @bid_pack.id, error_log[:bid_pack_id]
    assert_equal "pi_shared", error_log[:stripe_payment_intent_id]
    assert_equal "cs_shared", error_log[:stripe_checkout_session_id]
    assert_equal "evt_shared", error_log[:stripe_event_id]
  end

  test "sets receipt_status unavailable when Stripe returns no receipt URL" do
    fake_payment_intent = OpenStruct.new(latest_charge: nil, charges: OpenStruct.new(data: []))

    Stripe.stub(:api_key, "sk_test") do
      Stripe::PaymentIntent.stub(:retrieve, ->(*_) { fake_payment_intent }) do
        result = Payments::ApplyBidPackPurchase.call!(
          user: @user,
          bid_pack: @bid_pack,
          stripe_checkout_session_id: "cs_999",
          stripe_payment_intent_id: "pi_999",
          stripe_event_id: nil,
          amount_cents: 100,
          currency: "usd",
          source: "test"
        )

        assert result.ok?
      end
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_999")
    assert_equal "unavailable", purchase.receipt_status
    assert_nil purchase.receipt_url
  end

  test "keeps receipt_status pending when Stripe receipt lookup fails transiently" do
    Stripe.stub(:api_key, "sk_test") do
      Stripe::PaymentIntent.stub(:retrieve, ->(*_) { raise Stripe::StripeError, "timeout" }) do
        result = Payments::ApplyBidPackPurchase.call!(
          user: @user,
          bid_pack: @bid_pack,
          stripe_checkout_session_id: "cs_timeout",
          stripe_payment_intent_id: "pi_timeout",
          stripe_event_id: nil,
          amount_cents: 100,
          currency: "usd",
          source: "test"
        )

        assert result.ok?
      end
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_timeout")
    assert_equal "pending", purchase.receipt_status
    assert_nil purchase.receipt_url
  end

  test "captures stripe_charge_id when Stripe provides latest_charge" do
    fake_charge = OpenStruct.new(id: "ch_123", receipt_url: "https://stripe.com/receipt/ch_123")
    fake_payment_intent = OpenStruct.new(latest_charge: fake_charge)

    Stripe.stub(:api_key, "sk_test") do
      Stripe::PaymentIntent.stub(:retrieve, ->(*_) { fake_payment_intent }) do
        result = Payments::ApplyBidPackPurchase.call!(
          user: @user,
          bid_pack: @bid_pack,
          stripe_checkout_session_id: "cs_charge",
          stripe_payment_intent_id: "pi_charge",
          stripe_event_id: nil,
          amount_cents: 100,
          currency: "usd",
          source: "test"
        )

        assert result.ok?
      end
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_charge")
    assert_equal "ch_123", purchase.stripe_charge_id
    assert_equal "available", purchase.receipt_status
    assert_equal "https://stripe.com/receipt/ch_123", purchase.receipt_url
  end

  test "captures stripe_charge_id when Stripe returns latest_charge id string" do
    fake_payment_intent = OpenStruct.new(latest_charge: "ch_string")
    fake_charge = OpenStruct.new(id: "ch_string", receipt_url: nil)

    Stripe.stub(:api_key, "sk_test") do
      Stripe::PaymentIntent.stub(:retrieve, ->(*_) { fake_payment_intent }) do
        Stripe::Charge.stub(:retrieve, ->(*_) { fake_charge }) do
          result = Payments::ApplyBidPackPurchase.call!(
            user: @user,
            bid_pack: @bid_pack,
            stripe_checkout_session_id: "cs_charge_string",
            stripe_payment_intent_id: "pi_charge_string",
            stripe_event_id: nil,
            amount_cents: 100,
            currency: "usd",
            source: "test"
          )

          assert result.ok?
        end
      end
    end

    purchase = Purchase.find_by!(stripe_payment_intent_id: "pi_charge_string")
    assert_equal "ch_string", purchase.stripe_charge_id
    assert_equal "unavailable", purchase.receipt_status
    assert_nil purchase.receipt_url
  end
end
