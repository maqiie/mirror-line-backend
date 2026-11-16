require "securerandom"
require "digest"

class PasswordResetToken < ApplicationRecord
  belongs_to :user

  TTL = 30.minutes

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.issue!(user:)
    raw_token = SecureRandom.urlsafe_base64(48)

    record = user.password_reset_tokens.create!(
      token_digest: digest(raw_token),
      expires_at: TTL.from_now
    )

    [record, raw_token]
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.find_usable(raw_token)
    return if raw_token.blank?

    find_by(
      token_digest: digest(raw_token),
      used_at: nil
    )&.then { |record| record if record.expires_at.future? }
  end

  def consume!
    now = Time.current

    self.class.where(id: id, used_at: nil)
      .where("expires_at > ?", now)
      .update_all(used_at: now, updated_at: now) == 1
  end
end
