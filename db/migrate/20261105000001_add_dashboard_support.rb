class AddDashboardSupport < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :copier_paused, :boolean, null: false, default: false

    add_column :trading_accounts, :guards, :jsonb, null: false, default: {}      # risk limits pushed to the slave EA
    add_column :trading_accounts, :positions, :jsonb, null: false, default: []   # every open position, from the heartbeat
    add_column :trading_accounts, :quotes, :jsonb, null: false, default: {}      # latest prices for watched symbols
    add_column :trading_accounts, :last_equity_sample_at, :datetime

    add_column :copy_links, :max_slippage, :integer, null: false, default: 20
    add_column :copy_links, :symbol_suffix, :string, null: false, default: ""

    add_column :trade_events, :profit, :decimal, precision: 20, scale: 2         # realised profit on close events

    add_column :commands, :batch_key, :string                                    # groups one dashboard order sent to many accounts
    add_column :commands, :target_ticket, :bigint                                # raw broker ticket for close_ticket
    add_column :commands, :max_slippage, :integer
    add_column :commands, :symbol_suffix, :string
    add_index  :commands, :batch_key, where: "batch_key IS NOT NULL"

    create_table :equity_samples do |t|
      t.references :trading_account, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :at, null: false
      t.decimal :equity, precision: 20, scale: 2, null: false
    end
    add_index :equity_samples, %i[trading_account_id at]
  end
end
