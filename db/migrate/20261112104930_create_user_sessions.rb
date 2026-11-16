class CreateUserSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true

      t.string :access_token_digest, null: false
      t.string :refresh_token_digest, null: false

      t.datetime :access_expires_at, null: false
      t.datetime :refresh_expires_at, null: false

      t.datetime :revoked_at
      t.datetime :last_used_at

      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :user_sessions, :access_token_digest, unique: true
    add_index :user_sessions, :refresh_token_digest, unique: true
    add_index :user_sessions, [:user_id, :revoked_at]
  end
end