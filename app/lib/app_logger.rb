class AppLogger
  class << self
    def log(event:, level: :info, **context)
      merged_context = compact_hash(current_context.merge(context))
      payload = { event: event }.merge(merged_context)
      Rails.logger.public_send(level, payload.to_json)
    end

    def error(event:, error:, **context)
      log(
        event: event,
        level: :error,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(5),
        **context
      )
    end

    private

    def current_context
      return {} unless defined?(Current)

      {
        request_id: Current.request_id,
        user_id: Current.user_id,
        session_token_id: Current.session_token_id
      }
    end

    def compact_hash(hash)
      hash.compact
    end
  end
end
