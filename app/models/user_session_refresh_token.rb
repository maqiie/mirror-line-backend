
class UserSessionRefreshToken < ApplicationRecord
  belongs_to :user_session

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def usable?
    consumed_at.nil? && expires_at.future?
  end

def consume!
  now = Time.current

  self.class.where(
    id: id,
    consumed_at: nil
  ).where("expires_at > ?", now)
   .update_all(consumed_at: now, updated_at: now) == 1
end
  
end
