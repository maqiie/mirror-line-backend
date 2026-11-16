require "securerandom"
require "digest"

class UserSession < ApplicationRecord
  belongs_to :user

  has_many :refresh_tokens,
           class_name: "UserSessionRefreshToken",
           dependent: :destroy

  ACCESS_TOKEN_TTL = 15.minutes
  REFRESH_TOKEN_TTL = 30.days

  validates :access_token_digest, presence: true, uniqueness: true
  validates :refresh_token_digest, presence: true, uniqueness: true
  validates :access_expires_at, :refresh_expires_at, presence: true

  def self.issue!(user:, ip_address: nil, user_agent: nil)
    access_token = SecureRandom.urlsafe_base64(48)
    refresh_token = SecureRandom.urlsafe_base64(48)

    session = transaction do
      created_session = create!(
        user: user,
        access_token_digest: digest(access_token),
        refresh_token_digest: digest(refresh_token),
        access_expires_at: ACCESS_TOKEN_TTL.from_now,
        refresh_expires_at: REFRESH_TOKEN_TTL.from_now,
        ip_address: ip_address,
        user_agent: user_agent
      )

      created_session.refresh_tokens.create!(
        token_digest: digest(refresh_token),
        expires_at: created_session.refresh_expires_at
      )

      created_session
    end

    [session, access_token, refresh_token]
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.find_active_by_access_token(token)
    return if token.blank?

    session = find_by(access_token_digest: digest(token))
    return unless session&.access_valid?

    session
  end
  def self.rotate_refresh_token!(raw_token)
    return if raw_token.blank?

    token_digest = digest(raw_token)
    token_record = UserSessionRefreshToken.find_by(token_digest: token_digest)
    return unless token_record

    session = token_record.user_session

    session.with_lock do
      token_record.reload

      unless session.refresh_valid?
        next nil
      end

      # Reuse of an already-consumed token revokes this session.
      if token_record.consumed_at.present?
        session.revoke!
        next nil
      end

      # Reject expired or otherwise unusable tokens.
      unless token_record.usable?
        next nil
      end

      new_access_token = SecureRandom.urlsafe_base64(48)
      new_refresh_token = SecureRandom.urlsafe_base64(48)

            unless token_record.consume!
        session.revoke!
        next nil
      end

      session.update!(
        access_token_digest: digest(new_access_token),
        refresh_token_digest: digest(new_refresh_token),
        access_expires_at: ACCESS_TOKEN_TTL.from_now,
        last_used_at: Time.current
      )

      session.refresh_tokens.create!(
        token_digest: digest(new_refresh_token),
        expires_at: session.refresh_expires_at
      )

      [session, new_access_token, new_refresh_token]
    end
  end

  def access_valid?
    revoked_at.nil? &&
      access_expires_at.future? &&
      refresh_expires_at.future?
  end

  def refresh_valid?
    revoked_at.nil? && refresh_expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at?
  end
end