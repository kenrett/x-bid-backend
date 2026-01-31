require "uri"
require "redis"

namespace :jobs do
  desc "Preflight check for production job infrastructure (Redis + adapter)"
  task preflight: :environment do
    adapter = ActiveJob::Base.queue_adapter_name
    puts "ActiveJob adapter: #{adapter}"

    redis_url = ENV["REDIS_URL"].to_s
    if redis_url.empty?
      raise "REDIS_URL is not set"
    end

    begin
      uri = URI.parse(redis_url)
      redis = Redis.new(url: redis_url)
      redis.ping
      host = uri.host || "unknown"
      port = uri.port || "unknown"
      puts "Redis reachable: true (#{host}:#{port})"
    rescue StandardError => e
      puts "Redis reachable: false (#{e.class})"
      raise
    end

    queue_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "queue").first
    if queue_config
      begin
        ActiveRecord::Base.connected_to(database: :queue) do
          ActiveRecord::Base.connection.execute("SELECT 1")
        end
        puts "Queue database reachable: true"
      rescue StandardError => e
        puts "Queue database reachable: false (#{e.class})"
        raise
      end
    else
      puts "Queue database reachable: false (not configured)"
    end
  end

  desc "Enqueue and verify a Solid Queue job executes"
  task smoke: :environment do
    token = SecureRandom.hex(8)
    key = "solid_queue_smoke:#{token}"
    Rails.cache.delete(key)

    SolidQueueSmokeJob.perform_later(token)

    deadline = Time.current + 15.seconds
    loop do
      break if Rails.cache.read(key).present?
      if Time.current >= deadline
        raise "Smoke job did not run within 15 seconds"
      end
      sleep 0.5
    end

    puts "Solid Queue smoke test passed (token #{token})"
  end
end
