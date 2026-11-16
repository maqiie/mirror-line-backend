class AddEmailVerificationToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :email_verified_at, :datetime

    # Preserve access for users who already have accounts.
    execute <<~SQL
      UPDATE users
      SET email_verified_at = CURRENT_TIMESTAMP
      WHERE email_verified_at IS NULL
    SQL

    create_table :email_verification_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :email_verification_tokens, :token_digest, unique: true
    add_index :email_verification_tokens, [:user_id, :used_at]
  end

  def down
    drop_table :email_verification_tokens
    remove_column :users, :email_verified_at
  end
end
