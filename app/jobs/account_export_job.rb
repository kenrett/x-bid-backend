class AccountExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    export = AccountExport.find_by(id: export_id)
    return unless export
    return unless export.pending?

    payload = Account::ExportPayload.new(user: export.user).call
    export.update!(
      status: :ready,
      ready_at: Time.current,
      payload: payload
    )
  rescue StandardError => e
    export&.update!(status: :failed, error_message: e.message)
    AppLogger.error(event: "account.export.generate_failed", error: e, export_id: export_id)
  end
end
