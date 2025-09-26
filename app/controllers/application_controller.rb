class ApplicationController < ActionController::API
  def authenticate_request!
    header = request.headers["Authorization"]
    return render json: { error: "Authorization header missing" }, status: :unauthorized unless header

    token = header.split(" ").last
    return render json: { error: "Token missing from Authorization header" }, status: :unauthorized unless token

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base)[0]
      @current_user = User.find_by(id: decoded["user_id"])
    rescue ActiveRecord::RecordNotFound, JWT::DecodeError
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  private

  def current_user
    @current_user
  end
end
