class ApplicationController < ActionController::API
  include ErrorRenderer
  include ActionController::Cookies
  attr_reader :current_session_token
  before_action :set_storefront_context
  before_action :set_request_context
  before_action :enforce_maintenance_mode
  after_action :set_request_id_header
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_parse_error

  CABLE_SESSION_COOKIE_NAME = "cable_session"
  CABLE_SESSION_COOKIE_PATH = "/cable"
  BROWSER_SESSION_COOKIE_NAME = "bs_session_id"

  def authenticate_request!
    begin
      session_token = Auth::AuthenticateRequest.call(request)
      unless session_token
        return render_auth_failure!(
          code: :invalid_token,
          reason: missing_credentials_reason,
          message: "Authorization header or session cookie missing",
          status: :unauthorized
        )
      end

      unless session_token&.active?
        SessionEventBroadcaster.session_invalidated(session_token, reason: "expired") if session_token
        return render_auth_failure!(
          code: :invalid_session,
          reason: :expired_session,
          message: "Session has expired",
          status: :unauthorized
        )
      end

      @current_session_token = session_token
      @current_user = session_token.user
      set_authenticated_request_context!
      track_session_token!(session_token)
      if @current_user.disabled?
        session_token.revoke! unless session_token.revoked_at?
        AppLogger.log(event: "auth.session.revoked", user_id: @current_user.id, session_token_id: session_token.id, reason: "user_disabled")
        SessionEventBroadcaster.session_invalidated(session_token, reason: "user_disabled")
        render_error(code: :account_disabled, message: "User account disabled", status: :forbidden)
      end
    rescue JWT::ExpiredSignature
      render_auth_failure!(
        code: :invalid_token,
        reason: :expired_session,
        message: "Token has expired",
        status: :unauthorized
      )
    rescue JWT::DecodeError, JWT::VerificationError => e
      render_auth_failure!(
        code: :invalid_token,
        reason: :bad_token_format,
        message: "Invalid token: #{e.message}",
        status: :unauthorized,
        log_details: { error_class: e.class.name }
      )
    rescue ActiveRecord::RecordNotFound
      render_auth_failure!(
        code: :invalid_token,
        reason: :unknown_session,
        message: "Unauthorized",
        status: :unauthorized
      )
    end
  end

  private

  def set_storefront_context
    Current.storefront_key ||= Storefront::Resolver.resolve(request)
  end

  def set_request_context
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end

  def set_request_id_header
    return if response.headers["X-Request-Id"].present?

    response.set_header("X-Request-Id", request.request_id)
  end

  def set_authenticated_request_context!
    Current.user_id = @current_user&.id
    Current.session_token_id = @current_session_token&.id
  end

  def current_user
    @current_user
  end

  def require_verified_email!
    return if @current_user&.email_verified?

    render_error(code: :email_unverified, message: "Verify your email to continue.", status: :forbidden)
  end

  def authorize_admin!
    authorize!(:admin)
  end

  def authorize_superadmin!
    authorize!(:superadmin)
  end

  def authorize!(role, message: nil)
    return true if Authorization::Guard.allow?(actor: @current_user, role: role)

    render_error(
      code: :forbidden,
      message: (message || Authorization::Guard.default_forbidden_message(role)),
      status: :forbidden
    )
    false
  end

  def enforce_maintenance_mode
    return unless maintenance_enabled?
    return if path_allowed_during_maintenance?
    return if maintenance_admin_override?

    render_error(code: :maintenance_mode, message: "Maintenance in progress", status: :service_unavailable)
  end

  def maintenance_enabled?
    cached = Rails.cache.read("maintenance_mode.enabled")
    return cached unless cached.nil?

    MaintenanceSetting.global.enabled
  end

  def maintenance_admin_override?
    session_token = Auth::AuthenticateRequest.call(request)
    return false unless session_token&.active?

    user = session_token.user
    @current_session_token ||= session_token
    @current_user ||= user
    set_authenticated_request_context!
    Authorization::Guard.allow?(actor: user, role: :admin)
  rescue StandardError
    false
  end

  def path_allowed_during_maintenance?
    return true if request.path == "/up"
    return true if request.path == "/api/v1/health"
    return true if request.path == "/api/v1/login"
    return true if request.path == "/api/v1/signup"
    return true if request.path == "/api/v1/email_verifications/verify"
    return true if request.path == "/api/v1/admin/maintenance"
    return true if request.path == "/api/v1/maintenance"
    return true if request.path == "/api/v1/stripe/webhooks"

    false
  end

  def track_session_token!(session_token)
    return unless session_token

    now = Time.current
    debounce_seconds = (ENV["SESSION_LAST_SEEN_DEBOUNCE_SECONDS"].presence || 60).to_i
    debounce_seconds = 60 if debounce_seconds <= 0

    updates = {}

    user_agent = request.user_agent
    ip_address = request.remote_ip

    updates[:user_agent] = user_agent if user_agent.present? && user_agent != session_token.user_agent
    updates[:ip_address] = ip_address if ip_address.present? && ip_address != session_token.ip_address

    last_seen_at = session_token.last_seen_at
    should_touch_last_seen = last_seen_at.nil? || last_seen_at <= (now - debounce_seconds.seconds)
    if should_touch_last_seen
      updates[:last_seen_at] = now
      updates[:updated_at] = now
    end

    return if updates.empty?

    session_token.update_columns(updates)
  rescue StandardError => e
    AppLogger.error(event: "auth.session_token.track_failed", error: e, session_token_id: session_token&.id)
  end

  def extract_authorization_token
    header = request.headers["Authorization"]
    return nil if header.blank?

    header.split(" ").last
  end

  def session_token_from_jwt(token)
    Auth::SessionTokenDecoder.session_token_from_jwt(token)
  end

  def browser_session_cookie_present?
    request.cookies.key?(BROWSER_SESSION_COOKIE_NAME)
  end

  def handle_parameter_missing(exception)
    render_error(code: :bad_request, message: exception.message, status: :bad_request)
  end

  def handle_record_not_found(_exception)
    render_error(code: :not_found, message: "Not found", status: :not_found)
  end

  def handle_parse_error(_exception)
    render_error(code: :bad_request, message: "Malformed JSON", status: :bad_request)
  end

  def render_auth_failure!(code:, reason:, message:, status:, log_details: {})
    log_auth_failure(code: code, reason: reason, log_details: log_details)
    render_error(
      code: code,
      message: message,
      status: status,
      details: auth_failure_response_details(reason)
    )
  end

  def auth_failure_response_details(reason)
    details = { reason: reason.to_s, request_id: request.request_id }
    storefront_key = Current.storefront_key if defined?(Current)
    details[:storefront_key] = storefront_key if storefront_key.present?
    details
  end

  def log_auth_failure(code:, reason:, log_details: {})
    auth_header_present = request.headers["Authorization"].present?
    cookie_header_present = request.headers["Cookie"].present?
    cable_cookie_present = cookies.signed[CABLE_SESSION_COOKIE_NAME].present?
    browser_cookie_present = browser_session_cookie_present?

    AppLogger.log(
      event: "auth.failure",
      level: :warn,
      code: code.to_s,
      reason: reason.to_s,
      request_id: request.request_id,
      controller_action: "#{controller_name}##{action_name}",
      controller: controller_name,
      action: action_name,
      method: request.request_method,
      path: request.fullpath,
      origin: request.headers["Origin"],
      host: request.host,
      cookie_present: cookie_header_present,
      authorization_present: auth_header_present,
      cable_session_cookie_present: cable_cookie_present,
      browser_session_cookie_present: browser_cookie_present,
      storefront_key: Current.storefront_key,
      **log_details
    )
  end

  def missing_credentials_reason
    auth_header_present = request.headers["Authorization"].present?
    cookie_header_present = request.headers["Cookie"].present?
    cable_cookie_present = cookies.signed[CABLE_SESSION_COOKIE_NAME].present?
    browser_cookie_present = browser_session_cookie_present?

    return :bad_token_format if auth_header_present && extract_authorization_token.blank?
    return :unknown_session if auth_header_present
    return :unknown_session if cable_cookie_present || browser_cookie_present
    return :missing_session_cookie if cookie_header_present

    :missing_authorization_header
  end

  def set_cable_session_cookie(session_token)
    return unless session_token

    cookies.signed[CABLE_SESSION_COOKIE_NAME] = {
      value: session_token.id,
      expires: session_token.expires_at,
      httponly: true,
      secure: Rails.env.production?,
      # SameSite=Lax keeps the cookie on same-site subdomains while preventing cross-site leakage.
      same_site: :lax,
      path: CABLE_SESSION_COOKIE_PATH
    }
  end

  def set_browser_session_cookie(session_token)
    return unless session_token

    cookies.signed[BROWSER_SESSION_COOKIE_NAME] = {
      value: session_token.id,
      expires: session_token.expires_at,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax,
      domain: CookieDomainResolver.domain_for(request.host)
    }.compact
  end

  def clear_cable_session_cookie
    cookies.signed[CABLE_SESSION_COOKIE_NAME] = {
      value: "",
      expires: 1.day.ago,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax,
      path: CABLE_SESSION_COOKIE_PATH
    }
  end

  def clear_browser_session_cookie
    cookies.signed[BROWSER_SESSION_COOKIE_NAME] = {
      value: "",
      expires: 1.day.ago,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax,
      domain: CookieDomainResolver.domain_for(request.host)
    }.compact
  end

  def encode_jwt(payload = {}, expires_at: nil, **kwargs)
    payload = (payload || {}).to_h.merge(kwargs)
    expiration_time = (expires_at || 24.hours.from_now).to_i
    payload_with_exp = payload.merge(exp: expiration_time)
    # Explicitly set the algorithm for better security. HS256 is the default, but it's best practice to be explicit.
    JWT.encode(payload_with_exp, Rails.application.secret_key_base, "HS256")
  end
end
