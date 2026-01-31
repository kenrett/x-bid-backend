module Account
  class DeleteAccount
    CONFIRMATION_STRING = "DELETE"

    def initialize(user:, current_password:, confirmation:)
      @user = user
      @current_password = current_password
      @confirmation = confirmation
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user
      return ServiceResult.fail("Invalid password", code: :invalid_password) unless @user.authenticate(@current_password.to_s)
      return ServiceResult.fail("Confirmation mismatch", code: :validation_error) unless @confirmation.to_s == CONFIRMATION_STRING

      @user.disable_revoke_and_anonymize!
      AppLogger.log(event: "account.deleted", user_id: @user.id)
      AuditLogger.log(action: "account.deleted", actor: @user, user: @user, payload: { user_id: @user.id })

      ServiceResult.ok(code: :deleted)
    rescue StandardError => e
      AppLogger.error(event: "account.delete.failed", error: e, user_id: @user&.id)
      ServiceResult.fail("Unable to delete account", code: :unexpected_error)
    end
  end
end
