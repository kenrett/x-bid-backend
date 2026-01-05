default_enabled = Rails.env.production? ? "true" : "false"
return unless ENV.fetch("LOG_HOMEPAGE_P95", default_enabled) == "true"

require Rails.root.join("app/lib/p95_latency_tracker")

tracker = P95LatencyTracker.new(
  window_size: ENV.fetch("HOMEPAGE_P95_WINDOW", 500),
  log_interval: ENV.fetch("HOMEPAGE_P95_LOG_INTERVAL_SECONDS", 60).to_i.seconds
)

tracked_actions = {
  [ "Api::V1::AuctionsController", "index" ] => "homepage.auctions_index",
  [ "Api::V1::BidPacksController", "index" ] => "homepage.bid_packs_index"
}.freeze

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload

  key = tracked_actions[[ payload[:controller], payload[:action] ]]
  next unless key

  tracker.observe(key: key, duration_ms: event.duration)
end
