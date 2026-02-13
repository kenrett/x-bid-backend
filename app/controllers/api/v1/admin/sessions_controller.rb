module Api
  module V1
    module Admin
      class SessionsController < BaseController
        # POST /api/v1/admin/sessions/revoke_all
        # @summary Revoke all active sessions globally
        # Emergency kill-switch that forces every currently authenticated user to re-authenticate.
        # @request_body Global revoke request (application/json) [Hash{ reason: String, rotate_signing_secrets: Boolean }]
        # @response Sessions revoked (200) [Hash{ status: String, sessions_revoked: Integer, revoked_at: String, reason: String, rotate_signing_secrets: Boolean, secret_rotation_note: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Unprocessable content (422) [Error]
        def revoke_all
          result = Auth::GlobalSessionRevoke.new(
            actor: @current_user,
            reason: revoke_all_params[:reason],
            rotate_signing_secrets: revoke_all_params[:rotate_signing_secrets],
            request: request,
            triggered_via: "admin_api",
            triggered_by: @current_user&.email_address
          ).call
          return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

          render json: {
            status: "revoked",
            sessions_revoked: result[:revoked_count],
            revoked_at: result[:revoked_at]&.iso8601,
            reason: result[:reason],
            rotate_signing_secrets: result[:rotate_signing_secrets],
            secret_rotation_note: result[:secret_rotation_note]
          }.compact, status: :ok
        end

        private

        def required_role
          :superadmin
        end

        def revoke_all_params
          raw = params.fetch(:session, params).permit(:reason, :rotate_signing_secrets, :rotateSigningSecrets)
          raw.to_h.tap do |hash|
            hash["rotate_signing_secrets"] = hash.delete("rotateSigningSecrets") if hash.key?("rotateSigningSecrets")
          end.with_indifferent_access
        end
      end
    end
  end
end
