class AuditLogger
  def self.log(action:, actor:, target: nil, payload: {})
    AuditLog.create!(
      action: action,
      actor: actor,
      target: target,
      payload: payload || {}
    )
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("AuditLogger failure: #{e.message}")
    nil
  end
end
