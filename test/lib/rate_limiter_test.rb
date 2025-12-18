require "test_helper"

class RateLimiterTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    @redis = FakeRedis.new
    RateLimiter.redis = @redis
  end

  def teardown
    RateLimiter.redis = nil
    travel_back
  end

  test "allows the first N calls" do
    travel_to Time.utc(2024, 1, 1, 0, 0, 0)

    3.times do
      assert RateLimiter.allow!(key: "user:1", limit: 3, period_seconds: 60)
    end
  end

  test "blocks when the limit is exceeded" do
    travel_to Time.utc(2024, 1, 1, 0, 0, 0)

    assert RateLimiter.allow!(key: "user:2", limit: 2, period_seconds: 60)
    assert RateLimiter.allow!(key: "user:2", limit: 2, period_seconds: 60)
    refute RateLimiter.allow!(key: "user:2", limit: 2, period_seconds: 60)

    assert_raises RateLimiter::LimitExceeded do
      RateLimiter.allow!(key: "user:2", limit: 2, period_seconds: 60, raise_on_limit: true)
    end
  end

  test "resets when the period rolls over" do
    travel_to Time.utc(2024, 1, 1, 0, 0, 0)

    assert RateLimiter.allow!(key: "user:3", limit: 1, period_seconds: 30)
    refute RateLimiter.allow!(key: "user:3", limit: 1, period_seconds: 30)

    travel 31.seconds

    assert RateLimiter.allow!(key: "user:3", limit: 1, period_seconds: 30)
  end

  test "accounts for custom costs" do
    travel_to Time.utc(2024, 1, 1, 0, 0, 0)

    assert RateLimiter.allow!(key: "user:4", limit: 5, period_seconds: 60, cost: 3)
    refute RateLimiter.allow!(key: "user:4", limit: 5, period_seconds: 60, cost: 3)
    assert_equal 0, RateLimiter.remaining(key: "user:4", limit: 5, period_seconds: 60)
  end
end

class FakeRedis
  def initialize
    @data = {}
    @expires_at = {}
  end

  def incrby(key, value)
    prune(key)
    @data[key] = (@data[key] || 0) + value
  end

  def expire(key, ttl)
    return false unless @data.key?(key)

    @expires_at[key] = now + ttl
    true
  end

  def ttl(key)
    prune(key)
    return -2 unless @data.key?(key)

    return -1 unless @expires_at.key?(key)

    remaining = (@expires_at[key] - now).ceil
    remaining.positive? ? remaining : -2
  end

  def get(key)
    prune(key)
    value = @data[key]
    value&.to_s
  end

  private

  def prune(key)
    return unless @expires_at[key]

    if now >= @expires_at[key]
      @expires_at.delete(key)
      @data.delete(key)
    end
  end

  def now
    Time.now.to_f
  end
end
