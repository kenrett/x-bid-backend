module Account
  class CreateExport
    REUSE_WINDOW_SECONDS = 1.hour.to_i

    def initialize(user:, environment:)
      @user = user
      @environment = environment
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      export = reuse_recent_export || AccountExport.create!(user: @user, status: :pending, requested_at: Time.current)
      AuditLogger.log(
        action: "account.export.requested",
        actor: @user,
        user: @user,
        target: export,
        payload: { status: export.status }
      )

      if export.pending? && !@environment.production?
        generate_sync(export)
      elsif export.pending?
        AccountExportJob.perform_later(export.id)
      end

      ServiceResult.ok(code: :accepted, data: { export_payload: Account::ExportPresenter.new(export: export).payload })
    rescue StandardError => e
      AppLogger.error(event: "account.export.create_failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to create export", code: :unexpected_error)
    end

    private

    def generate_sync(export)
      payload = Account::ExportPayload.new(user: @user).call
      export.update!(
        status: :ready,
        ready_at: Time.current,
        payload: payload
      )
    rescue StandardError => e
      export.update!(status: :failed, error_message: e.message)
    end

    def reuse_recent_export
      @user.account_exports
        .where(status: [ :pending, :ready ])
        .where("requested_at >= ?", Time.current - REUSE_WINDOW_SECONDS)
        .order(requested_at: :desc)
        .first
    end
  end
end
