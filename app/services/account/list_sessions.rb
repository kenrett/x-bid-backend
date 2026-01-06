module Account
  class ListSessions
    USER_AGENT_SUMMARY_MAX = 80

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
          user_agent_summary: summarize_user_agent(session_token.user_agent),
          ip_address: session_token.ip_address,
          current: @current_session_token.present? && session_token.id == @current_session_token.id
        }
      end
    end

    private

    def summarize_user_agent(user_agent)
      ua = user_agent.to_s.strip
      return nil if ua.blank?

      ua = ua.gsub(/\s+/, " ")
      return ua if ua.length <= USER_AGENT_SUMMARY_MAX

      ua.slice(0, USER_AGENT_SUMMARY_MAX - 1) + "…"
    end
  end
end
