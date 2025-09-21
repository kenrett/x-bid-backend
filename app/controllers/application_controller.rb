class ApplicationController < ActionController::API
  def authenticate_request!
    header = request.headers["Authorization"]
    token = header.split(" ").last if header
    decoded = JWT.decode(token, Rails.application.secret_key_base)[0] rescue nil
    @current_user = User.find(decoded["user_id"]) if decoded
  rescue
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
