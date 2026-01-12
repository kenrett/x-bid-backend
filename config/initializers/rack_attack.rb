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

  message =
    case request.path
    when %r{\A/api/v1/login\z}
      "Too many login attempts. Please try again soon."
    when %r{\A/api/v1/(signup|users)\z}
      "Too many signup attempts. Please try again soon."
    when %r{\A/api/v1/password/(forgot|reset)\z}
      "Too many password attempts. Please slow down and try again."
    when %r{\A/api/v1/auctions/\d+/bids\z}
      "Too many bid attempts. Please wait before bidding again."
    when %r{\A/api/v1/checkout(?:s|/status|/success)?\z}
      "Too many checkout attempts. Please try again soon."
    when %r{\A/api/v1/session/remaining\z}
      "Too many session checks. Please try again later."
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
  def self.env_int(name, default)
    raw = ENV[name]
    return default if raw.blank?

    Integer(raw, 10)
  rescue ArgumentError, TypeError
    default
  end

  def self.env_seconds(name, default_seconds)
    env_int(name, default_seconds).seconds
  end

  EXPENSIVE_PATHS = {
    login: %r{\A/api/v1/login\z},
    signup: %r{\A/api/v1/(signup|users)\z},
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

  def self.signup?(req)
    req.post? && req.path.match?(EXPENSIVE_PATHS[:signup])
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
    user_params = req.params["user"]
    user_email = user_params["email_address"] if user_params.is_a?(Hash)

    email = req.params.dig("session", "email_address") ||
      user_email ||
      password_email ||
      req.params["email_address"] ||
      req.params["email"]
    trimmed = email.to_s.strip
    trimmed.empty? ? nil : trimmed.downcase
  end

  def self.jwt_user_id(req)
    header = req.env["HTTP_AUTHORIZATION"].to_s
    token = header.split(" ").last
    return nil if token.blank?

    decoded =
      JWT.decode(
        token,
        Rails.application.secret_key_base,
        true,
        {
          algorithm: "HS256",
          verify_expiration: false,
          verify_iat: false,
          verify_not_before: false
        }
      ).first

    decoded["user_id"]
  rescue JWT::DecodeError, JWT::VerificationError, ArgumentError
    nil
  end
end

Rack::Attack.safelist("allow-healthcheck") { |req| req.path == "/up" }

Rack::Attack.throttle(
  "requests/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_REQUESTS_IP_LIMIT", 300),
  period: RackAttackRules.env_seconds("RATE_LIMIT_REQUESTS_IP_PERIOD_SECONDS", 5.minutes.to_i)
) do |req|
  # Exclude session remaining checks from the global rate limit to prevent
  # a frontend polling bug from locking the user out of the entire application.
  if req.path != "/api/v1/session/remaining"
    req.ip
  end
end

Rack::Attack.throttle(
  "expensive/ip/short",
  limit: RackAttackRules.env_int("RATE_LIMIT_EXPENSIVE_IP_SHORT_LIMIT", 25),
  period: RackAttackRules.env_seconds("RATE_LIMIT_EXPENSIVE_IP_SHORT_PERIOD_SECONDS", 1.minute.to_i)
) do |req|
  req.ip if RackAttackRules.expensive?(req)
end

Rack::Attack.throttle(
  "expensive/ip/long",
  limit: RackAttackRules.env_int("RATE_LIMIT_EXPENSIVE_IP_LONG_LIMIT", 150),
  period: RackAttackRules.env_seconds("RATE_LIMIT_EXPENSIVE_IP_LONG_PERIOD_SECONDS", 1.hour.to_i)
) do |req|
  req.ip if RackAttackRules.expensive?(req)
end

Rack::Attack.throttle(
  "login/ip/short",
  limit: RackAttackRules.env_int("RATE_LIMIT_LOGIN_IP_SHORT_LIMIT", 20),
  period: RackAttackRules.env_seconds("RATE_LIMIT_LOGIN_IP_SHORT_PERIOD_SECONDS", 30.seconds.to_i)
) do |req|
  req.ip if RackAttackRules.login?(req)
end

Rack::Attack.throttle(
  "login/email/short",
  limit: RackAttackRules.env_int("RATE_LIMIT_LOGIN_EMAIL_SHORT_LIMIT", 8),
  period: RackAttackRules.env_seconds("RATE_LIMIT_LOGIN_EMAIL_SHORT_PERIOD_SECONDS", 10.minutes.to_i)
) do |req|
  RackAttackRules.normalized_email(req) if RackAttackRules.login?(req)
end

Rack::Attack.throttle(
  "signup/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_SIGNUP_IP_LIMIT", 10),
  period: RackAttackRules.env_seconds("RATE_LIMIT_SIGNUP_IP_PERIOD_SECONDS", 10.minutes.to_i)
) do |req|
  req.ip if RackAttackRules.signup?(req)
end

Rack::Attack.throttle(
  "signup/email",
  limit: RackAttackRules.env_int("RATE_LIMIT_SIGNUP_EMAIL_LIMIT", 6),
  period: RackAttackRules.env_seconds("RATE_LIMIT_SIGNUP_EMAIL_PERIOD_SECONDS", 1.hour.to_i)
) do |req|
  RackAttackRules.normalized_email(req) if RackAttackRules.signup?(req)
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

Rack::Attack.throttle(
  "password_reset/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_PASSWORD_RESET_IP_LIMIT", 10),
  period: RackAttackRules.env_seconds("RATE_LIMIT_PASSWORD_RESET_IP_PERIOD_SECONDS", 10.minutes.to_i)
) do |req|
  req.ip if RackAttackRules.password_reset?(req)
end

Rack::Attack.throttle(
  "password_reset/email",
  limit: RackAttackRules.env_int("RATE_LIMIT_PASSWORD_RESET_EMAIL_LIMIT", 6),
  period: RackAttackRules.env_seconds("RATE_LIMIT_PASSWORD_RESET_EMAIL_PERIOD_SECONDS", 30.minutes.to_i)
) do |req|
  RackAttackRules.normalized_email(req) if RackAttackRules.password_reset?(req)
end

# Bidding is hot; keep a short window but allow a handful before throttling.
Rack::Attack.throttle(
  "bids/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_BIDS_IP_LIMIT", 50),
  period: RackAttackRules.env_seconds("RATE_LIMIT_BIDS_IP_PERIOD_SECONDS", 1.minute.to_i)
) do |req|
  req.ip if RackAttackRules.bidding?(req)
end

Rack::Attack.throttle(
  "bids/user",
  limit: RackAttackRules.env_int("RATE_LIMIT_BIDS_USER_LIMIT", 50),
  period: RackAttackRules.env_seconds("RATE_LIMIT_BIDS_USER_PERIOD_SECONDS", 1.minute.to_i)
) do |req|
  RackAttackRules.jwt_user_id(req) if RackAttackRules.bidding?(req)
end

Rack::Attack.throttle(
  "checkout/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_CHECKOUT_IP_LIMIT", 15),
  period: RackAttackRules.env_seconds("RATE_LIMIT_CHECKOUT_IP_PERIOD_SECONDS", 10.minutes.to_i)
) do |req|
  req.ip if RackAttackRules.checkout?(req)
end

Rack::Attack.throttle(
  "session_remaining/ip",
  limit: RackAttackRules.env_int("RATE_LIMIT_SESSION_REMAINING_IP_LIMIT", 60),
  period: RackAttackRules.env_seconds("RATE_LIMIT_SESSION_REMAINING_IP_PERIOD_SECONDS", 1.minute.to_i)
) do |req|
  req.ip if req.path == "/api/v1/session/remaining"
end
