require "test_helper"

class RateLimitCounterTest < ActiveSupport::TestCase
  test "allows requests within the configured limit" do
    key = "password-reset-ip:192.0.2.1"

    assert RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )

    assert RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )

    assert RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )
  end

  test "blocks requests exceeding the configured limit" do
    key = "password-reset-ip:192.0.2.2"

    3.times do
      RateLimitCounter.allow_request?(
        key: key,
        limit: 3,
        period: 15.minutes
      )
    end

    assert_not RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )
  end

  test "resets the counter after the window expires" do
    key = "password-reset-ip:192.0.2.3"

    3.times do
      RateLimitCounter.allow_request?(
        key: key,
        limit: 3,
        period: 15.minutes
      )
    end

    counter = RateLimitCounter.find_by!(
      key_digest: Digest::SHA256.hexdigest(key)
    )

    counter.update!(window_started_at: 16.minutes.ago)

    assert RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )

    assert_equal 1, counter.reload.request_count
  end

  test "keeps separate counters for separate keys" do
    assert RateLimitCounter.allow_request?(
      key: "password-reset-ip:192.0.2.4",
      limit: 1,
      period: 15.minutes
    )

    assert RateLimitCounter.allow_request?(
      key: "password-reset-ip:192.0.2.5",
      limit: 1,
      period: 15.minutes
    )
  end

  test "stores only a digest of the rate-limit key" do
    key = "password-reset-email:user@example.com"

    RateLimitCounter.allow_request?(
      key: key,
      limit: 3,
      period: 15.minutes
    )

    counter = RateLimitCounter.last

    assert_equal Digest::SHA256.hexdigest(key), counter.key_digest
    assert_not_equal key, counter.key_digest
  end

  test "rejects invalid limits and periods" do
    assert_raises(ArgumentError) do
      RateLimitCounter.allow_request?(
        key: "test",
        limit: 0,
        period: 15.minutes
      )
    end

    assert_raises(ArgumentError) do
      RateLimitCounter.allow_request?(
        key: "test",
        limit: 3,
        period: 0
      )
    end
  end
end
