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

ActiveRecord::Schema[8.0].define(version: 2025_09_24_214045) do
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

  create_table "bid_packs", force: :cascade do |t|
    t.string "name"
    t.integer "bids"
    t.decimal "price", precision: 6, scale: 2
    t.boolean "highlight"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "bid_credits", default: 0, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "auctions", "users", column: "winning_user_id"
  add_foreign_key "bids", "auctions"
  add_foreign_key "bids", "users"
end
