class ApplicationController < ActionController::API
  attr_reader :current_session_token

  def authenticate_request!
    header = request.headers["Authorization"]
    return render json: { error: "Authorization header missing" }, status: :unauthorized unless header

    token = header.split(" ").last
    return render json: { error: "Token missing from Authorization header" }, status: :unauthorized unless token

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })[0]
      session_token = SessionToken.find_by(id: decoded["session_token_id"])
      unless session_token&.active?
        SessionEventBroadcaster.session_invalidated(session_token, reason: "expired") if session_token
        return render json: { error: "Session has expired" }, status: :unauthorized
      end

      @current_session_token = session_token
      @current_user = session_token.user
    rescue JWT::ExpiredSignature
      render json: { error: "Token has expired" }, status: :unauthorized
    rescue JWT::DecodeError => e
      render json: { error: "Invalid token: #{e.message}" }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  private

  def current_user
    @current_user
  end

  def authorize_admin!
    return if @current_user&.admin? || @current_user&.superadmin?

    render json: { error: "Admin privileges required" }, status: :forbidden
  end

  def authorize_superadmin!
    return if @current_user&.superadmin?

    render json: { error: "Superadmin privileges required" }, status: :forbidden
  end

  def encode_jwt(payload, expires_at: nil)
    expiration_time = (expires_at || 24.hours.from_now).to_i
    payload_with_exp = payload.merge(exp: expiration_time)
    # Explicitly set the algorithm for better security. HS256 is the default, but it's best practice to be explicit.
    JWT.encode(payload_with_exp, Rails.application.secret_key_base, 'HS256')
  end
end
