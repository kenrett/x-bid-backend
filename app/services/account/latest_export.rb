module Account
  class LatestExport
    def initialize(user:)
      @user = user
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      export = @user.account_exports.order(requested_at: :desc).first
      payload = export ? Account::ExportPresenter.new(export: export).payload : nil

      ServiceResult.ok(code: :ok, data: { export_payload: payload })
    end
  end
end
