Apipie.configure do |config|
  config.app_name     = "XBid API"
  config.api_base_url = "/api/v1"
  config.doc_base_url = "/api-docs"

  # Restrict /api-docs to admin/superadmin using JWT/session auth.
  # Accepts Authorization header or ?token=<jwt> query param (useful when loading docs in a browser).
  config.authenticate = lambda do |controller|
    token = token_from_apipie_request(controller)
    unless token.present?
      controller.render json: { error: "Authorization token missing" }, status: :unauthorized
      next false
    end

    begin
      decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: "HS256" }).first
      session_token = SessionToken.find_by(id: decoded["session_token_id"])
      unless session_token&.active?
        controller.render json: { error: "Session has expired" }, status: :unauthorized
        next false
      end

      user = session_token.user
      unless user&.admin? || user&.superadmin?
        controller.render json: { error: "Admin privileges required" }, status: :forbidden
        next false
      end

      true
    rescue JWT::DecodeError => e
      controller.render json: { error: "Invalid token: #{e.message}" }, status: :unauthorized
      false
    rescue StandardError
      controller.render json: { error: "Unauthorized" }, status: :unauthorized
      false
    end
  end

  config.api_controllers_matcher = "#{Rails.root}/app/controllers/api/v1/**/*.rb"
end

def token_from_apipie_request(controller)
  header = controller.request.headers["Authorization"]
  return header.split(" ").last if header.present?

  controller.params[:token]
end
