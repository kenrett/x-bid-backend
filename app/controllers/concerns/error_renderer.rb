module ErrorRenderer
  extend ActiveSupport::Concern

  def render_error(code:, message:, status:, details: nil, field_errors: nil)
    normalized_status = status == :unprocessable_entity ? :unprocessable_content : status
    error = { code: code.to_s, message: message }
    error[:details] = details if details.present?
    error[:field_errors] = field_errors if field_errors.present?
    render json: { error: error }, status: normalized_status
  end
end
