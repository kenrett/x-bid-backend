# frozen_string_literal: true

Rails.configuration.x.session_token_ttl = begin
  minutes = ENV.fetch("SESSION_TOKEN_TTL_MINUTES", 30).to_i
  minutes.minutes
end
