class User < ApplicationRecord
  has_secure_password

  has_many :trading_accounts, dependent: :destroy
  has_many :copy_links, dependent: :destroy
  has_many :user_sessions, dependent: :destroy
  has_many :password_reset_tokens, dependent: :destroy
  has_many :email_verification_tokens, dependent: :destroy

  normalizes :email, with: ->(e) { e.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 10 }, allow_nil: true

  def email_verified?
    email_verified_at.present?
  end
end
