class P95LatencyTracker
  def initialize(window_size: 500, log_interval: 60.seconds)
    @window_size = window_size.to_i
    @log_interval_seconds = log_interval.to_i
    @mutex = Mutex.new
    @windows = Hash.new { |hash, key| hash[key] = [] }
    @last_logged_at = {}
  end

  def observe(key:, duration_ms:)
    now = Time.now.to_i

    values = nil
    should_log = false

    @mutex.synchronize do
      window = @windows[key]
      window << duration_ms.to_f
      window.shift while window.length > @window_size

      last = @last_logged_at.fetch(key, 0)
      should_log = (now - last) >= @log_interval_seconds && window.length >= 20
      if should_log
        @last_logged_at[key] = now
        values = window.dup
      end
    end

    return unless should_log && values

    AppLogger.log(
      event: "http.latency.p95",
      endpoint: key,
      sample_size: values.length,
      p50_ms: percentile(values, 50),
      p95_ms: percentile(values, 95),
      p99_ms: percentile(values, 99)
    )
  rescue StandardError => e
    AppLogger.error(event: "http.latency.p95_failed", error: e, endpoint: key)
  end

  private

  def percentile(values, percentile_rank)
    return nil if values.empty?

    sorted = values.sort
    index = ((percentile_rank.to_f / 100) * (sorted.length - 1)).round
    sorted.fetch(index).round(1)
  end
end
