class User < ApplicationRecord
  has_secure_password

  has_many :trading_accounts, dependent: :destroy
  has_many :copy_links, dependent: :destroy

  normalizes :email, with: ->(e) { e.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 10 }, allow_nil: true

  # Signed, expiring API token. Invalidated automatically when the password changes.
  generates_token_for :api, expires_in: 12.hours do
    password_salt&.last(10)
  end
end
