# frozen_string_literal: true

class SessionEventBroadcaster
  CHANNEL_PREFIX = "session_notifications".freeze

  def self.session_invalidated(session_token, reason: "invalidated")
    ActionCable.server.broadcast(channel_name(session_token), {
      type: "session_invalidated",
      session_token_id: session_token.id,
      session_expires_at: session_token.expires_at&.iso8601,
      reason: reason
    })
  end

  def self.channel_name(session_token_or_id)
    session_token_id = session_token_or_id.is_a?(SessionToken) ? session_token_or_id.id : session_token_or_id
    "#{CHANNEL_PREFIX}_#{session_token_id}"
  end
end
