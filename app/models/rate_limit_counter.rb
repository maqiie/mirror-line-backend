require "digest"

class RateLimitCounter < ApplicationRecord
  validates :key_digest, presence: true
  validates :window_started_at, presence: true
  validates :request_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.allow_request?(key:, limit:, period:)
    raise ArgumentError, "limit must be positive" unless limit.to_i.positive?
    raise ArgumentError, "period must be positive" unless period.to_i.positive?

    now = Time.current
    digest = Digest::SHA256.hexdigest(key.to_s)

    counter = create_or_find_by!(key_digest: digest) do |record|
      record.window_started_at = now
      record.request_count = 0
    end

    counter.with_lock do
      if counter.window_started_at <= now - period
        counter.update!(
          window_started_at: now,
          request_count: 1
        )
      else
        counter.increment!(:request_count)
      end

      counter.request_count <= limit
    end
  end
end
