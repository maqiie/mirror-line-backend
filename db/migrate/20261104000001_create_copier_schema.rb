class CreateCopierSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :trading_accounts do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string  :name, null: false
      t.string  :platform, null: false, default: "mt5"
      t.string  :role, null: false                      # master | slave
      t.bigint  :login, null: false
      t.string  :broker
      t.string  :server
      t.string  :token_digest, null: false              # SHA256 of the EA token; raw token is never stored
      t.boolean :kill_switch, null: false, default: false
      t.boolean :paused, null: false, default: false
      t.boolean :daily_halt, null: false, default: false # reported by the slave EA
      t.decimal :balance, precision: 20, scale: 2
      t.decimal :equity, precision: 20, scale: 2
      t.decimal :margin_level, precision: 20, scale: 2
      t.integer :outbox_size, null: false, default: 0
      t.jsonb   :open_tickets, null: false, default: []    # master snapshot
      t.jsonb   :pending_tickets, null: false, default: [] # master snapshot
      t.jsonb   :copies, null: false, default: []          # slave snapshot: [{m,s,v,p}]
      t.datetime :last_seen_at                              # any EA call (liveness)
      t.datetime :last_snapshot_at                          # last heartbeat (snapshot time)
      t.datetime :last_reconciled_at
      t.timestamps
    end
    add_index :trading_accounts, :token_digest, unique: true
    add_index :trading_accounts, %i[user_id server login], unique: true

    create_table :copy_links do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :master_account, null: false, foreign_key: { to_table: :trading_accounts, on_delete: :cascade }
      t.references :slave_account,  null: false, foreign_key: { to_table: :trading_accounts, on_delete: :cascade }
      t.string  :lot_mode, null: false, default: "fixed"   # fixed | multiplier | balance | risk
      t.decimal :lot_value, precision: 20, scale: 8, null: false, default: 0.01
      t.boolean :reverse, null: false, default: false
      t.boolean :active, null: false, default: true
      t.boolean :copy_pending, null: false, default: true
      t.boolean :copy_missed_opens, null: false, default: false
      t.text    :symbols, array: true, null: false, default: []  # whitelist; empty = all
      t.timestamps
    end
    add_index :copy_links, %i[master_account_id slave_account_id], unique: true

    create_table :trade_events do |t|
      t.references :trading_account, null: false, foreign_key: { on_delete: :cascade }
      t.string  :event_type, null: false
      t.bigint  :master_ticket, null: false
      t.string  :symbol, null: false
      t.string  :side, null: false
      t.decimal :volume,      precision: 20, scale: 8
      t.decimal :prev_volume, precision: 20, scale: 8
      t.decimal :price, precision: 20, scale: 8
      t.decimal :sl,    precision: 20, scale: 8
      t.decimal :tp,    precision: 20, scale: 8
      t.decimal :master_balance, precision: 20, scale: 2
      t.decimal :master_equity,  precision: 20, scale: 2
      t.datetime :event_time
      t.string  :idempotency_key, null: false
      t.string  :platform
      t.jsonb   :payload, null: false, default: {}
      t.timestamps
    end
    add_index :trade_events, %i[trading_account_id idempotency_key], unique: true
    add_index :trade_events, %i[trading_account_id master_ticket]

    # One row per copied trade on a slave. Its id is the "ticket key" the slave EA
    # uses to find the trade again, which avoids ticket collisions across masters.
    create_table :trade_mappings do |t|
      t.references :trading_account, null: false, foreign_key: { on_delete: :cascade } # the slave
      t.references :copy_link, foreign_key: { on_delete: :nullify }                   # null = manual trade
      t.bigint  :master_ticket
      t.string  :symbol
      t.string  :side
      t.decimal :volume, precision: 20, scale: 8
      t.bigint  :slave_ticket
      t.string  :state, null: false, default: "open_requested"
      t.datetime :opened_at
      t.datetime :closed_at
      t.string  :close_reason
      t.timestamps
    end
    add_index :trade_mappings, %i[copy_link_id master_ticket], unique: true,
              where: "copy_link_id IS NOT NULL AND state IN ('pending_requested','pending','open_requested','open')",
              name: "idx_mappings_one_active_per_link_ticket"
    add_index :trade_mappings, %i[trading_account_id state]

    create_table :commands do |t|
      t.references :trading_account, null: false, foreign_key: { on_delete: :cascade } # target slave
      t.references :trade_event,   foreign_key: { on_delete: :nullify }
      t.references :copy_link,     foreign_key: { on_delete: :nullify }
      t.references :trade_mapping, foreign_key: { on_delete: :nullify }
      t.string  :action, null: false
      t.string  :status, null: false, default: "pending"
      t.string  :symbol
      t.string  :side
      t.decimal :volume, precision: 20, scale: 8
      t.decimal :price,  precision: 20, scale: 8
      t.decimal :sl,     precision: 20, scale: 8
      t.decimal :tp,     precision: 20, scale: 8
      t.string  :lot_mode
      t.decimal :lot_value, precision: 20, scale: 8
      t.decimal :master_balance, precision: 20, scale: 2
      t.boolean :reverse, null: false, default: false
      t.decimal :ratio, precision: 12, scale: 8, null: false, default: 0
      t.bigint  :slave_ticket
      t.decimal :executed_volume, precision: 20, scale: 8
      t.decimal :executed_price,  precision: 20, scale: 8
      t.string  :result_message
      t.integer :attempts, null: false, default: 0
      t.datetime :sent_at
      t.datetime :acked_at
      t.timestamps
    end
    add_index :commands, %i[trading_account_id status id]
    add_index :commands, %i[trade_event_id trading_account_id], unique: true,
              where: "trade_event_id IS NOT NULL", name: "idx_commands_one_per_event_per_slave"
  end
end
