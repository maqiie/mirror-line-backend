class CreateUserSessionRefreshTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :user_session_refresh_tokens do |t|
      t.references :user_session, null: false, foreign_key: true

      t.string :token_digest, null: false
      t.datetime :consumed_at
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :user_session_refresh_tokens, :token_digest, unique: true
    add_index :user_session_refresh_tokens, [:user_session_id, :consumed_at],
              name: "index_refresh_tokens_on_session_and_consumed"
  end
end
