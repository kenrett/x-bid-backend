module Account
  class ListSessions
    def initialize(user:, current_session_token:)
      @user = user
      @current_session_token = current_session_token
    end

    def call
      return [] unless @user

      @user.session_tokens.active.order(created_at: :desc).map do |session_token|
        {
          id: session_token.id,
          created_at: session_token.created_at.iso8601,
          last_seen_at: session_token.last_seen_at&.iso8601,
          user_agent: session_token.user_agent,
          ip_address: session_token.ip_address,
          current: @current_session_token.present? && session_token.id == @current_session_token.id
        }
      end
    end
  end
end
