module Middleware
  class RequestSizeLimiter
    DEFAULT_MAX_BYTES = 1 * 1024 * 1024

    def initialize(app, max_bytes: DEFAULT_MAX_BYTES)
      @app = app
      @max_bytes = max_bytes
    end

    def call(env)
      if too_large?(env)
        return [
          413,
          { "Content-Type" => "application/json" },
          [ { error: { code: "request_too_large", message: "Request entity too large" } }.to_json ]
        ]
      end

      @app.call(env)
    end

    private

    def too_large?(env)
      content_length = env["CONTENT_LENGTH"].to_i
      return true if content_length.positive? && content_length > @max_bytes

      input = env["rack.input"]
      return false unless input&.respond_to?(:size)

      size = input.size
      size && size > @max_bytes
    rescue StandardError
      false
    end
  end
end
