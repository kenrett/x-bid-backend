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

ActiveRecord::Schema[8.0].define(version: 2025_12_08_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["winning_user_id"], name: "index_auctions_on_winning_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id", null: false
    t.string "target_type"
    t.bigint "target_id"
    t.jsonb "payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ip_address"
    t.text "user_agent"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
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
    t.index ["active"], name: "index_bid_packs_on_active"
    t.index ["status"], name: "index_bid_packs_on_status"
  end

  create_table "bids", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "auction_id", null: false
    t.decimal "amount", precision: 6, scale: 2
    t.boolean "auto"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_id"], name: "index_bids_on_auction_id"
    t.index ["user_id"], name: "index_bids_on_user_id"
  end

  create_table "maintenance_settings", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_maintenance_settings_on_key", unique: true
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
    t.index ["bid_pack_id"], name: "index_purchases_on_bid_pack_id"
    t.index ["stripe_checkout_session_id"], name: "index_purchases_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_purchases_on_stripe_payment_intent_id", unique: true
    t.index ["user_id"], name: "index_purchases_on_user_id"
  end

  create_table "session_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_session_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_session_tokens_on_token_digest", unique: true
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
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["is_superuser"], name: "index_users_on_is_superuser"
    t.index ["status"], name: "index_users_on_status"
  end

  add_foreign_key "auctions", "users", column: "winning_user_id"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "bids", "auctions"
  add_foreign_key "bids", "users"
  add_foreign_key "password_reset_tokens", "users"
  add_foreign_key "purchases", "bid_packs"
  add_foreign_key "purchases", "users"
  add_foreign_key "session_tokens", "users"
end
