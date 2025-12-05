class AppLogger
  class << self
    def log(event:, level: :info, **context)
      payload = { event: event }.merge(compact_hash(context))
      Rails.logger.public_send(level, payload.to_json)
    end

    def error(event:, error:, **context)
      log(
        event: event,
        level: :error,
        error: error.message,
        backtrace: error.backtrace&.first(5),
        **context
      )
    end

    private

    def compact_hash(hash)
      hash.compact
    end
  end
end
