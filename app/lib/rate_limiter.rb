class RateLimiter
  class LimitExceeded < StandardError; end

  class << self
    attr_writer :redis

    def allow!(key:, limit:, period_seconds:, cost: 1, raise_on_limit: false)
      validate_arguments!(key: key, limit: limit, period_seconds: period_seconds, cost: cost)

      limit = limit.to_i
      period_seconds = period_seconds.to_i
      cost = cost.to_i

      namespaced_key = storage_key(key, period_seconds)
      new_total = redis.incrby(namespaced_key, cost)
      ensure_expiration(namespaced_key, period_seconds)

      allowed = new_total <= limit
      raise LimitExceeded, "Rate limit exceeded for #{key}" if !allowed && raise_on_limit

      allowed
    end

    def remaining(key:, limit:, period_seconds:)
      validate_arguments!(key: key, limit: limit, period_seconds: period_seconds, cost: 1)

      limit = limit.to_i
      period_seconds = period_seconds.to_i

      current = redis.get(storage_key(key, period_seconds)).to_i
      remaining = limit - current
      remaining.positive? ? remaining : 0
    end

    private

    def storage_key(key, period_seconds)
      window = (Time.now.to_i / period_seconds).floor
      "rl:#{key}:#{window}"
    end

    def ensure_expiration(key, ttl_seconds)
      ttl = redis.ttl(key)
      return if ttl.positive?

      redis.expire(key, ttl_seconds)
    end

    def redis
      @redis ||= if Rails.application.config.respond_to?(:redis) && Rails.application.config.redis
        Rails.application.config.redis
      else
        Redis.current
      end
    end

    def validate_arguments!(key:, limit:, period_seconds:, cost:)
      raise ArgumentError, "key is required" if key.nil? || key == ""
      raise ArgumentError, "limit must be positive" unless limit.to_i.positive?
      raise ArgumentError, "period_seconds must be positive" unless period_seconds.to_i.positive?
      raise ArgumentError, "cost must be positive" unless cost.to_i.positive?
    end
  end
end
