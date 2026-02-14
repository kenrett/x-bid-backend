require "jwt"

module Api
  module V1
    class SessionsController < ApplicationController
      before_action :authenticate_request!, only: [ :logged_in?, :destroy, :remaining ]
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/login
      # @summary Log in and create a session
      # Authenticates a user and returns session tokens plus user context.
      # @request_body Login payload (application/json) [!LoginRequest]
      # @response Session created (200) [UserSession]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Bad request (400) [Error]
      # @no_auth
      def create
        user = User.find_by(email_address: login_params[:email_address])
        if user&.disabled?
          return render_error(code: :account_disabled, message: "User account disabled", status: :forbidden)
        end

        if user&.authenticate(login_params[:password])
          two_factor_verified_at = nil
          if user.two_factor_enabled?
            two_factor_verified_at = verify_two_factor_for_login(user, login_params)
            return if performed?
          end

          revoked_sessions = Auth::RevokeUserSessions.new(
            user: user,
            reason: "login_replaced",
            actor: user,
            request: request
          ).call
          session_token, refresh_token = SessionToken.generate_for(user:, two_factor_verified_at: two_factor_verified_at)
          track_session_token!(session_token)
          set_cable_session_cookie(session_token)
          set_browser_session_cookie(session_token)
          response.set_header("X-Auth-Mode", "cookie")
          AuditLogger.log(
            action: "auth.login",
            actor: user,
            user: user,
            session_token_id: session_token.id,
            request: request,
            payload: {
              session_token_id: session_token.id,
              replaced_session_count: revoked_sessions
            }
          )
          render json: Auth::SessionResponseBuilder.build(user:, session_token:, refresh_token:, jwt_encoder: method(:encode_jwt))
        else
          render_error(code: :invalid_credentials, message: "Invalid credentials", status: :unauthorized)
        end
      end

      # @summary Refresh the current session using a refresh token
      # Exchanges a valid refresh token for a new session token pair.
      # @request_body Refresh payload (application/json) [!RefreshRequest]
      # @response Session refreshed (200) [UserSession]
      # @response Unauthorized (401) [Error]
      # @response Forbidden (403) [Error]
      # @response Bad request (400) [Error]
      # @no_auth
      def refresh
        session_token = SessionToken.find_active_by_raw_token(refresh_params[:refresh_token])
        return render_error(code: :invalid_session, message: "Invalid or expired session", status: :unauthorized) unless session_token
        if session_token.user.disabled?
          session_token.revoke!
          SessionEventBroadcaster.session_invalidated(session_token, reason: "user_disabled")
          return render_error(code: :account_disabled, message: "User account disabled", status: :forbidden)
        end

        if session_token.user.two_factor_enabled? && session_token.two_factor_verified_at.blank?
          return render_error(code: :two_factor_required, message: "Two-factor authentication required", status: :unauthorized)
        end

        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "refresh_replaced")

        new_session_token, refresh_token = SessionToken.generate_for(
          user: session_token.user,
          two_factor_verified_at: session_token.two_factor_verified_at
        )
        track_session_token!(new_session_token)
        set_cable_session_cookie(new_session_token)
        set_browser_session_cookie(new_session_token)
        response.set_header("X-Auth-Mode", "cookie")
        AuditLogger.log(
          action: "auth.refresh",
          actor: session_token.user,
          user: session_token.user,
          session_token_id: new_session_token.id,
          request: request,
          payload: {
            replaced_session_token_id: session_token.id,
            session_token_id: new_session_token.id
          }
        )
        payload = Auth::SessionResponseBuilder.build(
          user: session_token.user,
          session_token: new_session_token,
          refresh_token: refresh_token,
          jwt_encoder: method(:encode_jwt)
        )

        render json: payload
      end

      # GET /api/v1/logged_in
      # @summary Check whether the provided token is valid
      # Returns session and user context if the token is valid.
      # @response Session valid (200) [LoggedInStatus]
      # @response Unauthorized (401) [Error]
      def logged_in?
        if @current_user
          render json: build_logged_in_response(@current_user, @current_session_token)
        else
          render json: { logged_in: false }, status: :unauthorized
        end
      end

      # @summary Return remaining time for the current session token
      # Provides session token metadata for the authenticated user.
      # @response Session timing (200) [Hash{ remaining_seconds: Integer, session_expires_at: String, session_token_id: Integer, user: Hash, is_admin: Boolean, is_superuser: Boolean }]
      # @response Unauthorized (401) [Error]
      def remaining
        render json: Auth::SessionResponseBuilder.remaining_data(user: @current_user, session_token: @current_session_token)
      end

      # DELETE /api/v1/logout
      # @summary Log out and revoke the current session token
      # Revokes the active session token and returns a confirmation message.
      # @response Logged out (200) [Hash{ status: String }]
      # @response Unauthorized (401) [Error]
      def destroy
        if @current_session_token
          @current_session_token.revoke!
          SessionEventBroadcaster.session_invalidated(@current_session_token, reason: "logout")
          AuditLogger.log(
            action: "auth.logout",
            actor: @current_user,
            user: @current_user,
            session_token_id: @current_session_token.id,
            request: request,
            payload: { revoked_session_token_id: @current_session_token.id }
          )
        end

        clear_cable_session_cookie
        clear_browser_session_cookie
        render json: { status: "Logged out successfully" }, status: :ok
      end

      private

      def login_params
        raw = (params[:session].presence || params).permit(:email_address, :emailAddress, :password, :otp, :recovery_code, :recoveryCode)
        raw.to_h.tap do |hash|
          hash["email_address"] ||= hash.delete("emailAddress")
          hash["recovery_code"] ||= hash.delete("recoveryCode")
        end
      end

      def refresh_params
        raw = (params[:session].presence || params).permit(:refresh_token, :refreshToken)
        raw.to_h.tap do |hash|
          hash["refresh_token"] ||= hash.delete("refreshToken")
        end
      end

      def build_logged_in_response(user, session_token)
        flags = Auth::SessionResponseBuilder.flags_for(user)
        {
          logged_in: true,
          user: Auth::SessionResponseBuilder.user_data(user, flags: flags),
          session_expires_at: session_token&.expires_at&.iso8601
        }
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end

      def verify_two_factor_for_login(user, params_hash)
        otp = params_hash["otp"].to_s
        recovery_code = params_hash["recovery_code"].to_s

        if otp.blank? && recovery_code.blank?
          render_error(code: :two_factor_required, message: "Two-factor authentication required", status: :unauthorized)
          return nil
        end

        if otp.present? && user.verify_two_factor_code(otp)
          return Time.current
        end

        if recovery_code.present? && user.consume_recovery_code!(recovery_code)
          return Time.current
        end

        render_error(code: :invalid_two_factor_code, message: "Invalid verification code", status: :unauthorized)
        nil
      end
    end
  end
end
