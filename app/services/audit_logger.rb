class AuditLogger
  def self.log(action:, actor: nil, user: nil, session_token_id: nil, request_id: nil, target: nil, payload: {}, request: nil)
    user_id = user&.id || actor&.id

    AuditLog.create!(
      action: action,
      actor: actor,
      user_id: user_id,
      session_token_id: session_token_id || Current.session_token_id,
      request_id: request_id || request&.request_id || Current.request_id,
      storefront_key: Current.storefront_key.to_s.presence,
      target: target,
      payload: payload || {},
      ip_address: request&.remote_ip || Current.ip_address,
      user_agent: request&.user_agent || Current.user_agent
    )
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("AuditLogger failure: #{e.message}")
    nil
  end
end
