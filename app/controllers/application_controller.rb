class ApplicationController < ActionController::API
  include ErrorRenderer
  attr_reader :current_session_token
  before_action :set_request_context
  before_action :enforce_maintenance_mode
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_parse_error

  def authenticate_request!
    header = request.headers["Authorization"]
    return render_error(code: :invalid_token, message: "Authorization header missing", status: :unauthorized) unless header

    token = header.split(" ").last
    return render_error(code: :invalid_token, message: "Token missing from Authorization header", status: :unauthorized) unless token

    begin
      decoded = JWT.decode(
        token,
        Rails.application.secret_key_base,
        true,
        {
          algorithm: "HS256",
          verify_expiration: true,
          verify_iat: true,
          verify_not_before: true
        }
      )[0]
      session_token = SessionToken.find_by(id: decoded["session_token_id"])
      unless session_token&.active?
        SessionEventBroadcaster.session_invalidated(session_token, reason: "expired") if session_token
        return render_error(code: :invalid_session, message: "Session has expired", status: :unauthorized)
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
      render_error(code: :invalid_token, message: "Token has expired", status: :unauthorized)
    rescue JWT::DecodeError => e
      render_error(code: :invalid_token, message: "Invalid token: #{e.message}", status: :unauthorized)
    rescue ActiveRecord::RecordNotFound
      render_error(code: :invalid_token, message: "Unauthorized", status: :unauthorized)
    end
  end

  private

  def set_request_context
    Current.request_id = request.request_id
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

    render_error(code: :email_unverified, message: "Email verification required", status: :forbidden)
  end

  def authorize_admin!
    return if @current_user&.admin? || @current_user&.superadmin?

    render_error(code: :forbidden, message: "Admin privileges required", status: :forbidden)
  end

  def authorize_superadmin!
    return if @current_user&.superadmin?

    render_error(code: :forbidden, message: "Superadmin privileges required", status: :forbidden)
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
    header = request.headers["Authorization"]
    return false unless header

    token = header.split(" ").last
    decoded = JWT.decode(
      token,
      Rails.application.secret_key_base,
      true,
      {
        algorithm: "HS256",
        verify_expiration: true,
        verify_iat: true,
        verify_not_before: true
      }
    ).first
    session_token = SessionToken.find_by(id: decoded["session_token_id"])
    return false unless session_token&.active?

    user = session_token.user
    @current_session_token ||= session_token
    @current_user ||= user
    set_authenticated_request_context!
    user.admin? || user.superadmin?
  rescue StandardError
    false
  end

  def path_allowed_during_maintenance?
    return true if request.path == "/up"
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
    updates = { last_seen_at: now, updated_at: now }

    user_agent = request.user_agent
    ip_address = request.remote_ip

    updates[:user_agent] = user_agent if user_agent.present? && user_agent != session_token.user_agent
    updates[:ip_address] = ip_address if ip_address.present? && ip_address != session_token.ip_address

    session_token.update_columns(updates)
  rescue StandardError => e
    AppLogger.error(event: "auth.session_token.track_failed", error: e, session_token_id: session_token&.id)
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

  def encode_jwt(payload = {}, expires_at: nil, **kwargs)
    payload = (payload || {}).to_h.merge(kwargs)
    expiration_time = (expires_at || 24.hours.from_now).to_i
    payload_with_exp = payload.merge(exp: expiration_time)
    # Explicitly set the algorithm for better security. HS256 is the default, but it's best practice to be explicit.
    JWT.encode(payload_with_exp, Rails.application.secret_key_base, "HS256")
  end
end
