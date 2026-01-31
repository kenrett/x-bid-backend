# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_01_31_153000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_exports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "requested_at", null: false
    t.datetime "ready_at"
    t.string "download_url"
    t.text "error_message"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_account_exports_on_status"
    t.index ["user_id", "requested_at"], name: "index_account_exports_on_user_id_and_requested_at"
    t.index ["user_id"], name: "index_account_exports_on_user_id"
  end

  create_table "activity_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_activity_events_on_event_type"
    t.index ["user_id", "occurred_at", "id"], name: "index_activity_events_on_user_id_and_occurred_at_and_id"
    t.index ["user_id", "occurred_at"], name: "index_activity_events_on_user_id_and_occurred_at"
    t.index ["user_id"], name: "index_activity_events_on_user_id"
  end

  create_table "auction_fulfillments", force: :cascade do |t|
    t.bigint "auction_settlement_id", null: false
    t.bigint "user_id", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "shipping_address"
    t.integer "shipping_cost_cents"
    t.string "shipping_carrier"
    t.string "tracking_number"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_settlement_id"], name: "index_auction_fulfillments_on_auction_settlement_id", unique: true
    t.index ["status"], name: "index_auction_fulfillments_on_status"
    t.index ["user_id"], name: "index_auction_fulfillments_on_user_id"
  end

  create_table "auction_settlements", force: :cascade do |t|
    t.bigint "auction_id", null: false
    t.bigint "winning_user_id"
    t.bigint "winning_bid_id"
    t.decimal "final_price", precision: 6, scale: 2, default: "0.0", null: false
    t.string "currency", default: "usd", null: false
    t.integer "status", default: 0, null: false
    t.datetime "ended_at", null: false
    t.string "payment_intent_id"
    t.datetime "paid_at"
    t.datetime "failed_at"
    t.string "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "fulfillment_status", default: 0, null: false
    t.jsonb "fulfillment_address"
    t.decimal "shipping_cost", precision: 6, scale: 2, default: "0.0", null: false
    t.string "shipping_carrier"
    t.string "tracking_number"
    t.string "storefront_key"
    t.index ["auction_id"], name: "index_auction_settlements_on_auction_id", unique: true
    t.index ["fulfillment_status"], name: "index_auction_settlements_on_fulfillment_status"
    t.index ["payment_intent_id"], name: "index_auction_settlements_on_payment_intent_id", unique: true
    t.index ["status"], name: "index_auction_settlements_on_status"
    t.index ["storefront_key"], name: "index_auction_settlements_on_storefront_key"
    t.index ["winning_bid_id"], name: "index_auction_settlements_on_winning_bid_id"
    t.index ["winning_user_id"], name: "index_auction_settlements_on_winning_user_id"
    t.check_constraint "storefront_key IS NOT NULL", name: "auction_settlements_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "auction_settlements_storefront_key_allowed"
  end

  create_table "auction_watches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "auction_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_id"], name: "index_auction_watches_on_auction_id"
    t.index ["user_id", "auction_id"], name: "index_auction_watches_on_user_id_and_auction_id", unique: true
    t.index ["user_id"], name: "index_auction_watches_on_user_id"
  end

  create_table "auctions", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "start_date"
    t.datetime "end_time"
    t.decimal "current_price", precision: 6, scale: 2
    t.string "image_url"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "winning_user_id"
    t.boolean "is_adult", default: false, null: false
    t.boolean "is_artisan", default: false, null: false
    t.string "storefront_key"
    t.index ["is_adult"], name: "index_auctions_on_is_adult"
    t.index ["is_artisan"], name: "index_auctions_on_is_artisan"
    t.index ["storefront_key"], name: "index_auctions_on_storefront_key"
    t.index ["winning_user_id"], name: "index_auctions_on_winning_user_id"
    t.check_constraint "current_price >= 0::numeric", name: "auctions_current_price_non_negative"
    t.check_constraint "storefront_key IS NOT NULL", name: "auctions_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "auctions_storefront_key_allowed"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "target_type"
    t.bigint "target_id"
    t.jsonb "payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ip_address"
    t.text "user_agent"
    t.string "request_id"
    t.bigint "session_token_id"
    t.bigint "user_id"
    t.string "storefront_key"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["session_token_id"], name: "index_audit_logs_on_session_token_id"
    t.index ["storefront_key", "created_at"], name: "index_audit_logs_on_storefront_key_and_created_at"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
    t.check_constraint "storefront_key IS NOT NULL", name: "audit_logs_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "audit_logs_storefront_key_allowed"
  end

  create_table "bid_packs", force: :cascade do |t|
    t.string "name"
    t.integer "bids"
    t.decimal "price", precision: 6, scale: 2
    t.boolean "highlight"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.integer "status", default: 0, null: false
    t.string "sku"
    t.string "storefront_key"
    t.index ["active"], name: "index_bid_packs_on_active"
    t.index ["sku"], name: "index_bid_packs_on_sku", unique: true
    t.index ["status"], name: "index_bid_packs_on_status"
    t.index ["storefront_key"], name: "index_bid_packs_on_storefront_key"
    t.check_constraint "storefront_key IS NOT NULL", name: "bid_packs_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "bid_packs_storefront_key_allowed"
  end

  create_table "bids", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "auction_id", null: false
    t.decimal "amount", precision: 6, scale: 2
    t.boolean "auto"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "storefront_key"
    t.index ["auction_id"], name: "index_bids_on_auction_id"
    t.index ["storefront_key"], name: "index_bids_on_storefront_key"
    t.index ["user_id"], name: "index_bids_on_user_id"
    t.check_constraint "amount >= 0::numeric", name: "bids_amount_non_negative"
    t.check_constraint "storefront_key IS NOT NULL", name: "bids_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "bids_storefront_key_allowed"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.integer "amount", null: false
    t.string "reason", null: false
    t.string "idempotency_key", null: false
    t.bigint "purchase_id"
    t.bigint "auction_id"
    t.bigint "admin_actor_id"
    t.bigint "stripe_event_id"
    t.string "stripe_payment_intent_id"
    t.string "stripe_checkout_session_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "storefront_key"
    t.index ["admin_actor_id"], name: "index_credit_transactions_on_admin_actor_id"
    t.index ["auction_id"], name: "index_credit_transactions_on_auction_id"
    t.index ["idempotency_key"], name: "unique_index_credit_transactions_on_idempotency_key", unique: true
    t.index ["purchase_id"], name: "index_credit_transactions_on_purchase_id"
    t.index ["purchase_id"], name: "uniq_ct_bpp_grant_purchase", unique: true, where: "((purchase_id IS NOT NULL) AND ((reason)::text = 'bid_pack_purchase'::text) AND ((kind)::text = 'grant'::text))"
    t.index ["storefront_key", "created_at"], name: "index_credit_transactions_on_storefront_key_and_created_at"
    t.index ["stripe_checkout_session_id"], name: "index_credit_transactions_on_stripe_checkout_session_id"
    t.index ["stripe_checkout_session_id"], name: "uniq_ct_bpp_grant_cs", unique: true, where: "((stripe_checkout_session_id IS NOT NULL) AND ((reason)::text = 'bid_pack_purchase'::text) AND ((kind)::text = 'grant'::text))"
    t.index ["stripe_event_id"], name: "index_credit_transactions_on_stripe_event_id"
    t.index ["stripe_payment_intent_id"], name: "index_credit_transactions_on_stripe_payment_intent_id"
    t.index ["stripe_payment_intent_id"], name: "uniq_ct_bpp_grant_pi", unique: true, where: "((stripe_payment_intent_id IS NOT NULL) AND ((reason)::text = 'bid_pack_purchase'::text) AND ((kind)::text = 'grant'::text))"
    t.index ["user_id", "created_at"], name: "index_credit_transactions_on_user_id_created_at"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
    t.check_constraint "storefront_key IS NOT NULL", name: "credit_transactions_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "credit_transactions_storefront_key_allowed"
  end

  create_table "maintenance_settings", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_maintenance_settings_on_key", unique: true
  end

  create_table "money_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "event_type", null: false
    t.integer "amount_cents", null: false
    t.string "currency", null: false
    t.string "source_type"
    t.string "source_id"
    t.jsonb "metadata"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "storefront_key"
    t.index ["event_type"], name: "index_money_events_on_event_type"
    t.index ["source_type", "source_id", "event_type"], name: "uniq_money_events_source_type_source_id_event_type", unique: true
    t.index ["source_type", "source_id"], name: "index_money_events_on_source"
    t.index ["storefront_key", "occurred_at"], name: "index_money_events_on_storefront_key_and_occurred_at"
    t.index ["user_id", "occurred_at"], name: "index_money_events_on_user_id_occurred_at"
    t.index ["user_id"], name: "index_money_events_on_user_id"
    t.check_constraint "char_length(currency::text) > 0", name: "money_events_currency_non_empty"
    t.check_constraint "event_type::text = ANY (ARRAY['purchase'::character varying::text, 'bid_spent'::character varying::text, 'refund'::character varying::text, 'admin_adjustment'::character varying::text])", name: "money_events_event_type_check"
    t.check_constraint "storefront_key IS NOT NULL", name: "money_events_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "money_events_storefront_key_allowed"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_notifications_on_kind"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "password_reset_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_password_reset_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_password_reset_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_password_reset_tokens_on_user_id"
  end

  create_table "purchases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "bid_pack_id", null: false
    t.string "stripe_checkout_session_id"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "amount_cents", default: 0, null: false
    t.string "currency", default: "usd", null: false
    t.integer "refunded_cents", default: 0, null: false
    t.string "refund_reason"
    t.string "refund_id"
    t.datetime "refunded_at"
    t.string "stripe_payment_intent_id"
    t.string "stripe_event_id"
    t.string "receipt_url"
    t.integer "receipt_status", default: 0, null: false
    t.string "stripe_charge_id"
    t.bigint "ledger_grant_credit_transaction_id"
    t.string "storefront_key"
    t.datetime "applied_at"
    t.index ["applied_at"], name: "index_purchases_on_applied_at"
    t.index ["bid_pack_id"], name: "index_purchases_on_bid_pack_id"
    t.index ["ledger_grant_credit_transaction_id"], name: "index_purchases_on_ledger_grant_credit_transaction_id"
    t.index ["receipt_status"], name: "index_purchases_on_receipt_status"
    t.index ["storefront_key", "created_at"], name: "index_purchases_on_storefront_key_and_created_at"
    t.index ["stripe_charge_id"], name: "index_purchases_on_stripe_charge_id"
    t.index ["stripe_checkout_session_id"], name: "index_purchases_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_event_id"], name: "index_purchases_on_stripe_event_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_purchases_on_stripe_payment_intent_id", unique: true
    t.index ["user_id"], name: "index_purchases_on_user_id"
    t.check_constraint "amount_cents >= 0", name: "purchases_amount_cents_non_negative"
    t.check_constraint "refunded_cents >= 0", name: "purchases_refunded_cents_non_negative"
    t.check_constraint "storefront_key IS NOT NULL", name: "purchases_storefront_key_not_null"
    t.check_constraint "storefront_key::text = ANY (ARRAY['main'::character varying, 'afterdark'::character varying, 'marketplace'::character varying]::text[])", name: "purchases_storefront_key_allowed"
  end

  create_table "session_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.datetime "age_verified_at"
    t.datetime "two_factor_verified_at"
    t.index ["expires_at"], name: "index_session_tokens_on_expires_at"
    t.index ["last_seen_at"], name: "index_session_tokens_on_last_seen_at"
    t.index ["token_digest"], name: "index_session_tokens_on_token_digest", unique: true
    t.index ["two_factor_verified_at"], name: "index_session_tokens_on_two_factor_verified_at"
    t.index ["user_id"], name: "index_session_tokens_on_user_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type"
    t.jsonb "payload", default: {}
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "bid_credits", default: 0, null: false
    t.boolean "is_superuser", default: false, null: false
    t.integer "status", default: 0, null: false
    t.datetime "email_verified_at"
    t.string "email_verification_token_digest"
    t.datetime "email_verification_sent_at"
    t.string "unverified_email_address"
    t.jsonb "notification_preferences", default: {"receipts" => true, "outbid_alerts" => true, "bidding_alerts" => true, "product_updates" => false, "marketing_emails" => false, "watched_auction_ending" => true}, null: false
    t.datetime "disabled_at"
    t.text "two_factor_secret_ciphertext"
    t.datetime "two_factor_enabled_at"
    t.jsonb "two_factor_recovery_codes", default: [], null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_verification_token_digest"], name: "index_users_on_email_verification_token_digest"
    t.index ["email_verified_at"], name: "index_users_on_email_verified_at"
    t.index ["is_superuser"], name: "index_users_on_is_superuser"
    t.index ["status"], name: "index_users_on_status"
    t.index ["unverified_email_address"], name: "index_users_on_unverified_email_address"
    t.check_constraint "bid_credits >= 0", name: "users_bid_credits_non_negative"
  end

  add_foreign_key "account_exports", "users"
  add_foreign_key "activity_events", "users"
  add_foreign_key "auction_fulfillments", "auction_settlements"
  add_foreign_key "auction_fulfillments", "users"
  add_foreign_key "auction_settlements", "auctions"
  add_foreign_key "auction_settlements", "bids", column: "winning_bid_id"
  add_foreign_key "auction_settlements", "users", column: "winning_user_id"
  add_foreign_key "auction_watches", "auctions"
  add_foreign_key "auction_watches", "users"
  add_foreign_key "auctions", "users", column: "winning_user_id"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "bids", "auctions"
  add_foreign_key "bids", "users"
  add_foreign_key "credit_transactions", "auctions"
  add_foreign_key "credit_transactions", "purchases"
  add_foreign_key "credit_transactions", "stripe_events"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "credit_transactions", "users", column: "admin_actor_id"
  add_foreign_key "money_events", "users"
  add_foreign_key "notifications", "users"
  add_foreign_key "password_reset_tokens", "users"
  add_foreign_key "purchases", "bid_packs"
  add_foreign_key "purchases", "credit_transactions", column: "ledger_grant_credit_transaction_id"
  add_foreign_key "purchases", "users"
  add_foreign_key "session_tokens", "users"
end
