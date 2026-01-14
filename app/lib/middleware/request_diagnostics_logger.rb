module Middleware
  class RequestDiagnosticsLogger
    def initialize(app)
      @app = app
    end

    def call(env)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = nil
      headers = nil
      response = nil
      error = nil

      begin
        status, headers, response = @app.call(env)
      rescue StandardError => e
        status = 500
        headers = {}
        response = nil
        error = e
        raise
      ensure
        log_request(env, status, headers, start, error: error)
      end

      [ status, headers, response ]
    end

    private

    def log_request(env, status, headers, start, error: nil)
      request = ActionDispatch::Request.new(env)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)

      auth_header = request.headers["Authorization"]
      cookie_header = request.headers["Cookie"]
      origin = request.headers["Origin"]

      pattern_match = origin.present? ? FrontendOrigins.allowed_origin_pattern_match(origin) : nil
      origin_allowed = origin.present? ? FrontendOrigins.allowed_origin?(origin) : nil
      origin_pattern_match = if pattern_match.is_a?(Regexp)
        pattern_match.source
      else
        pattern_match
      end
      origin_pattern_type = if pattern_match.is_a?(Regexp)
        "regex"
      elsif pattern_match.is_a?(String)
        "string"
      end

      options_requested_method = nil
      options_requested_headers = nil
      cors_response_headers = {}

      if request.request_method == "OPTIONS"
        options_requested_method = request.headers["Access-Control-Request-Method"]
        options_requested_headers = request.headers["Access-Control-Request-Headers"]
        cors_response_headers = {
          allow_origin: headers["Access-Control-Allow-Origin"],
          allow_credentials: headers["Access-Control-Allow-Credentials"],
          allow_headers: headers["Access-Control-Allow-Headers"],
          allow_methods: headers["Access-Control-Allow-Methods"]
        }.compact
      end

      controller_instance = env["action_controller.instance"]
      controller = controller_instance&.class&.name
      action = controller_instance&.action_name || env["action_dispatch.request.parameters"]&.dig("action")

      AppLogger.log(
        event: "http.request",
        request_id: request.request_id,
        method: request.request_method,
        path: request.fullpath,
        status: status,
        origin: origin,
        origin_allowed: origin_allowed,
        origin_pattern_match: origin_pattern_match,
        origin_pattern_type: origin_pattern_type,
        host: request.host,
        user_agent: request.user_agent,
        remote_ip: request.remote_ip,
        duration_ms: duration_ms,
        authorization_present: auth_header.present?,
        authorization_redacted: RequestDiagnostics.redact_authorization_header(auth_header),
        cookie_present: cookie_header.present?,
        cookie_names: RequestDiagnostics.cookie_names_from_header(cookie_header),
        options_requested_method: options_requested_method,
        options_requested_headers: options_requested_headers,
        cors_response_headers: cors_response_headers.presence,
        controller: controller,
        action: action,
        error_class: error&.class&.name
      )
    end
  end
end
