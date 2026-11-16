class CreateRateLimitCounters < ActiveRecord::Migration[7.2]
  def change
    create_table :rate_limit_counters do |t|
      t.string :key_digest, null: false
      t.datetime :window_started_at, null: false
      t.integer :request_count, null: false, default: 0

      t.timestamps
    end

    add_index :rate_limit_counters, :key_digest, unique: true
    add_check_constraint :rate_limit_counters,
      "request_count >= 0",
      name: "rate_limit_counters_request_count_nonnegative"
  end
end
