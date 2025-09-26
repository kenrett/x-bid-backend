class ApplicationController < ActionController::API
  def authenticate_request!
    header = request.headers["Authorization"]
    return render json: { error: "Authorization header missing" }, status: :unauthorized unless header

    token = header.split(" ").last
    return render json: { error: "Token missing from Authorization header" }, status: :unauthorized unless token

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })[0]
      @current_user = User.find_by(id: decoded["user_id"])
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
end
