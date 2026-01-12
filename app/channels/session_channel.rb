class SessionChannel < ApplicationCable::Channel
  def subscribed
    stream_from(SessionEventBroadcaster.channel_name(current_session_token.id))
  end
end
