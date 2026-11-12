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

ActiveRecord::Schema[7.2].define(version: 2026_11_05_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "commands", force: :cascade do |t|
    t.bigint "trading_account_id", null: false
    t.bigint "trade_event_id"
    t.bigint "copy_link_id"
    t.bigint "trade_mapping_id"
    t.string "action", null: false
    t.string "status", default: "pending", null: false
    t.string "symbol"
    t.string "side"
    t.decimal "volume", precision: 20, scale: 8
    t.decimal "price", precision: 20, scale: 8
    t.decimal "sl", precision: 20, scale: 8
    t.decimal "tp", precision: 20, scale: 8
    t.string "lot_mode"
    t.decimal "lot_value", precision: 20, scale: 8
    t.decimal "master_balance", precision: 20, scale: 2
    t.boolean "reverse", default: false, null: false
    t.decimal "ratio", precision: 12, scale: 8, default: "0.0", null: false
    t.bigint "slave_ticket"
    t.decimal "executed_volume", precision: 20, scale: 8
    t.decimal "executed_price", precision: 20, scale: 8
    t.string "result_message"
    t.integer "attempts", default: 0, null: false
    t.datetime "sent_at"
    t.datetime "acked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "batch_key"
    t.bigint "target_ticket"
    t.integer "max_slippage"
    t.string "symbol_suffix"
    t.index ["batch_key"], name: "index_commands_on_batch_key", where: "(batch_key IS NOT NULL)"
    t.index ["copy_link_id"], name: "index_commands_on_copy_link_id"
    t.index ["trade_event_id", "trading_account_id"], name: "idx_commands_one_per_event_per_slave", unique: true, where: "(trade_event_id IS NOT NULL)"
    t.index ["trade_event_id"], name: "index_commands_on_trade_event_id"
    t.index ["trade_mapping_id"], name: "index_commands_on_trade_mapping_id"
    t.index ["trading_account_id", "status", "id"], name: "index_commands_on_trading_account_id_and_status_and_id"
    t.index ["trading_account_id"], name: "index_commands_on_trading_account_id"
  end

  create_table "copy_links", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "master_account_id", null: false
    t.bigint "slave_account_id", null: false
    t.string "lot_mode", default: "fixed", null: false
    t.decimal "lot_value", precision: 20, scale: 8, default: "0.01", null: false
    t.boolean "reverse", default: false, null: false
    t.boolean "active", default: true, null: false
    t.boolean "copy_pending", default: true, null: false
    t.boolean "copy_missed_opens", default: false, null: false
    t.text "symbols", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_slippage", default: 20, null: false
    t.string "symbol_suffix", default: "", null: false
    t.index ["master_account_id", "slave_account_id"], name: "index_copy_links_on_master_account_id_and_slave_account_id", unique: true
    t.index ["master_account_id"], name: "index_copy_links_on_master_account_id"
    t.index ["slave_account_id"], name: "index_copy_links_on_slave_account_id"
    t.index ["user_id"], name: "index_copy_links_on_user_id"
  end

  create_table "equity_samples", force: :cascade do |t|
    t.bigint "trading_account_id", null: false
    t.datetime "at", null: false
    t.decimal "equity", precision: 20, scale: 2, null: false
    t.index ["trading_account_id", "at"], name: "index_equity_samples_on_trading_account_id_and_at"
    t.index ["trading_account_id"], name: "index_equity_samples_on_trading_account_id"
  end

  create_table "trade_events", force: :cascade do |t|
    t.bigint "trading_account_id", null: false
    t.string "event_type", null: false
    t.bigint "master_ticket", null: false
    t.string "symbol", null: false
    t.string "side", null: false
    t.decimal "volume", precision: 20, scale: 8
    t.decimal "prev_volume", precision: 20, scale: 8
    t.decimal "price", precision: 20, scale: 8
    t.decimal "sl", precision: 20, scale: 8
    t.decimal "tp", precision: 20, scale: 8
    t.decimal "master_balance", precision: 20, scale: 2
    t.decimal "master_equity", precision: 20, scale: 2
    t.datetime "event_time"
    t.string "idempotency_key", null: false
    t.string "platform"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "profit", precision: 20, scale: 2
    t.index ["trading_account_id", "idempotency_key"], name: "index_trade_events_on_trading_account_id_and_idempotency_key", unique: true
    t.index ["trading_account_id", "master_ticket"], name: "index_trade_events_on_trading_account_id_and_master_ticket"
    t.index ["trading_account_id"], name: "index_trade_events_on_trading_account_id"
  end

  create_table "trade_mappings", force: :cascade do |t|
    t.bigint "trading_account_id", null: false
    t.bigint "copy_link_id"
    t.bigint "master_ticket"
    t.string "symbol"
    t.string "side"
    t.decimal "volume", precision: 20, scale: 8
    t.bigint "slave_ticket"
    t.string "state", default: "open_requested", null: false
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.string "close_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["copy_link_id", "master_ticket"], name: "idx_mappings_one_active_per_link_ticket", unique: true, where: "((copy_link_id IS NOT NULL) AND ((state)::text = ANY ((ARRAY['pending_requested'::character varying, 'pending'::character varying, 'open_requested'::character varying, 'open'::character varying])::text[])))"
    t.index ["copy_link_id"], name: "index_trade_mappings_on_copy_link_id"
    t.index ["trading_account_id", "state"], name: "index_trade_mappings_on_trading_account_id_and_state"
    t.index ["trading_account_id"], name: "index_trade_mappings_on_trading_account_id"
  end

  create_table "trading_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "platform", default: "mt5", null: false
    t.string "role", null: false
    t.bigint "login", null: false
    t.string "broker"
    t.string "server"
    t.string "token_digest", null: false
    t.boolean "kill_switch", default: false, null: false
    t.boolean "paused", default: false, null: false
    t.boolean "daily_halt", default: false, null: false
    t.decimal "balance", precision: 20, scale: 2
    t.decimal "equity", precision: 20, scale: 2
    t.decimal "margin_level", precision: 20, scale: 2
    t.integer "outbox_size", default: 0, null: false
    t.jsonb "open_tickets", default: [], null: false
    t.jsonb "pending_tickets", default: [], null: false
    t.jsonb "copies", default: [], null: false
    t.datetime "last_seen_at"
    t.datetime "last_snapshot_at"
    t.datetime "last_reconciled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "guards", default: {}, null: false
    t.jsonb "positions", default: [], null: false
    t.jsonb "quotes", default: {}, null: false
    t.datetime "last_equity_sample_at"
    t.index ["token_digest"], name: "index_trading_accounts_on_token_digest", unique: true
    t.index ["user_id", "server", "login"], name: "index_trading_accounts_on_user_id_and_server_and_login", unique: true
    t.index ["user_id"], name: "index_trading_accounts_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "copier_paused", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "commands", "copy_links", on_delete: :nullify
  add_foreign_key "commands", "trade_events", on_delete: :nullify
  add_foreign_key "commands", "trade_mappings", on_delete: :nullify
  add_foreign_key "commands", "trading_accounts", on_delete: :cascade
  add_foreign_key "copy_links", "trading_accounts", column: "master_account_id", on_delete: :cascade
  add_foreign_key "copy_links", "trading_accounts", column: "slave_account_id", on_delete: :cascade
  add_foreign_key "copy_links", "users", on_delete: :cascade
  add_foreign_key "equity_samples", "trading_accounts", on_delete: :cascade
  add_foreign_key "trade_events", "trading_accounts", on_delete: :cascade
  add_foreign_key "trade_mappings", "copy_links", on_delete: :nullify
  add_foreign_key "trade_mappings", "trading_accounts", on_delete: :cascade
  add_foreign_key "trading_accounts", "users", on_delete: :cascade
end
