module Account
  class LatestExport
    def initialize(user:)
      @user = user
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      export = @user.account_exports.order(requested_at: :desc).first
      payload = export ? export_payload(export) : nil

      ServiceResult.ok(code: :ok, data: { export_payload: payload })
    end

    private

    def export_payload(export)
      payload = {
        id: export.id,
        status: export.status,
        requested_at: export.requested_at.iso8601,
        ready_at: export.ready_at&.iso8601,
        download_url: export.download_url
      }
      payload[:data] = export.payload if export.ready? && export.download_url.blank?
      payload
    end
  end
end
