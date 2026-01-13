class CableHealthController < ActionController::API
  def show
    Rails.logger.info(
      "ActionCable health check: host=#{request.host} origin=#{request.headers['Origin']}"
    )
    render json: { status: "ok" }
  end
end
