class AuditLogger
  def self.log(action:, actor:, target: nil, payload: {}, request: nil)
    AuditLog.create!(
      action: action,
      actor: actor,
      target: target,
      payload: payload || {},
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("AuditLogger failure: #{e.message}")
    nil
  end
end
