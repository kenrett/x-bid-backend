# frozen_string_literal: true

parse_positive_minutes = lambda do |value, default_minutes|
  minutes = value.to_i
  minutes = default_minutes if minutes <= 0
  minutes.minutes
end

idle_minutes = ENV["SESSION_TOKEN_IDLE_TTL_MINUTES"].presence || ENV["SESSION_TOKEN_TTL_MINUTES"]
Rails.configuration.x.session_token_idle_ttl = parse_positive_minutes.call(idle_minutes || 30, 30)
Rails.configuration.x.session_token_ttl = Rails.configuration.x.session_token_idle_ttl

absolute_minutes = ENV["SESSION_TOKEN_ABSOLUTE_TTL_MINUTES"]
Rails.configuration.x.session_token_absolute_ttl = parse_positive_minutes.call(absolute_minutes || (24 * 60), (24 * 60))
