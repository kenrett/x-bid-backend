module ErrorRenderer
  extend ActiveSupport::Concern

  def render_error(code:, message:, status:, details: nil)
    normalized_status = status == :unprocessable_entity ? :unprocessable_content : status
    payload = { error_code: code, message: message }
    payload[:details] = details if details.present?
    render json: payload, status: normalized_status
  end
end
