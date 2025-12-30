require "rack/attack"
# Use Rails.cache when available; fall back to an in-memory store in test so throttles
# actually count during specs.
Rack::Attack.cache.store =
  if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    ActiveSupport::Cache::MemoryStore.new
  else
    Rails.cache
  end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = (match_data[:period] || match_data["period"]).to_i
  name = match_data[:name] || match_data["name"]

  message = case name
  when /login/
              "Too many login attempts. Please try again soon."
  when /password/
              "Too many password attempts. Please slow down and try again."
  when /checkout/
              "Too many checkout attempts. Please try again soon."
  when /bid/
              "Too many bid attempts. Please wait before bidding again."
  else
              "Too many requests. Please try again later."
  end

  body = { error: { code: "rate_limited", message: message } }.to_json
  headers = { "Content-Type" => "application/json" }
  headers["Retry-After"] = retry_after.to_s if retry_after.positive?

  [ 429, headers, [ body ] ]
end

Rack::Attack.blocklisted_responder = lambda do |_request|
  body = { error: { code: "locked_out", message: "Too many failed attempts. Please try again later." } }.to_json
  [ 429, { "Content-Type" => "application/json" }, [ body ] ]
end

module RackAttackRules
  EXPENSIVE_PATHS = {
    login: %r{\A/api/v1/login\z},
    password_reset: %r{\A/api/v1/password/(forgot|reset)\z},
    bidding: %r{\A/api/v1/auctions/\d+/bids\z},
    checkout: %r{\A/api/v1/checkout(?:s|/status|/success)?\z}
  }.freeze

  def self.expensive?(req)
    EXPENSIVE_PATHS.reject { |key, _| key == :bidding }
                   .values
                   .any? { |pattern| req.path.match?(pattern) }
  end

  def self.login?(req)
    req.post? && req.path.match?(EXPENSIVE_PATHS[:login])
  end

  def self.password_reset?(req)
    req.path.match?(EXPENSIVE_PATHS[:password_reset])
  end

  def self.bidding?(req)
    req.post? && req.path.match?(EXPENSIVE_PATHS[:bidding])
  end

  def self.checkout?(req)
    req.path.match?(EXPENSIVE_PATHS[:checkout])
  end

  def self.normalized_email(req)
    password_params = req.params["password"]
    password_email = password_params["email_address"] if password_params.is_a?(Hash)

    email = req.params.dig("session", "email_address") ||
      password_email ||
      req.params["email_address"] ||
      req.params["email"]
    trimmed = email.to_s.strip
    trimmed.empty? ? nil : trimmed.downcase
  end
end

Rack::Attack.safelist("allow-healthcheck") { |req| req.path == "/up" }

Rack::Attack.throttle("requests/ip", limit: 300, period: 5.minutes) do |req|
  req.ip
end

Rack::Attack.throttle("expensive/ip/short", limit: 25, period: 1.minute) do |req|
  req.ip if RackAttackRules.expensive?(req)
end

Rack::Attack.throttle("expensive/ip/long", limit: 150, period: 1.hour) do |req|
  req.ip if RackAttackRules.expensive?(req)
end

Rack::Attack.throttle("login/ip/short", limit: 20, period: 30.seconds) do |req|
  req.ip if RackAttackRules.login?(req)
end

Rack::Attack.throttle("login/email/short", limit: 8, period: 10.minutes) do |req|
  RackAttackRules.normalized_email(req) if RackAttackRules.login?(req)
end

Rack::Attack.blocklist("lockout/login/ip") do |req|
  Rack::Attack::Allow2Ban.filter("lockout:login:ip:#{req.ip}", maxretry: 12, findtime: 15.minutes, bantime: 1.hour) do
    RackAttackRules.login?(req)
  end
end

Rack::Attack.blocklist("lockout/login/email") do |req|
  email = RackAttackRules.normalized_email(req)
  next false unless email

  Rack::Attack::Allow2Ban.filter("lockout:login:email:#{email}", maxretry: 10, findtime: 15.minutes, bantime: 1.hour) do
    RackAttackRules.login?(req)
  end
end

Rack::Attack.throttle("password_reset/ip", limit: 10, period: 10.minutes) do |req|
  req.ip if RackAttackRules.password_reset?(req)
end

Rack::Attack.throttle("password_reset/email", limit: 6, period: 30.minutes) do |req|
  RackAttackRules.normalized_email(req) if RackAttackRules.password_reset?(req)
end

# Bidding is hot; keep a short window but allow a handful before throttling.
Rack::Attack.throttle("bids/ip", limit: 50, period: 1.minute) do |req|
  req.ip if RackAttackRules.bidding?(req)
end

Rack::Attack.throttle("checkout/ip", limit: 15, period: 10.minutes) do |req|
  req.ip if RackAttackRules.checkout?(req)
end
