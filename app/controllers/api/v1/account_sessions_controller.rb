module Api
  module V1
    class AccountSessionsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # GET /api/v1/account/sessions
      # @summary List active sessions for the current user
      # @response Success (200) [AccountSessionsResponse]
      # @response Unauthorized (401) [Error]
      def index
        sessions = Account::ListSessions.new(user: @current_user, current_session_token: @current_session_token).call
        render json: { sessions: sessions }, status: :ok
      end

      # DELETE /api/v1/account/sessions/:id
      # @summary Revoke a session token for the current user
      # @parameter id(path) [Integer] Session token ID
      # @response Success (200) [Hash{ status: String }]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Unprocessable content (422) [Error]
      def destroy
        result = Account::RevokeSession.new(
          user: @current_user,
          current_session_token: @current_session_token,
          session_token_id: params.fetch(:id)
        ).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "revoked" }, status: :ok
      end

      # POST /api/v1/account/sessions/revoke_others
      # @summary Revoke all sessions except current
      # @response Success (200) [Hash{ status: String, sessions_revoked: Integer }]
      # @response Unauthorized (401) [Error]
      def revoke_others
        result = Account::RevokeOtherSessions.new(user: @current_user, current_session_token: @current_session_token).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "revoked", sessions_revoked: result.sessions_revoked }, status: :ok
      end

      private

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
