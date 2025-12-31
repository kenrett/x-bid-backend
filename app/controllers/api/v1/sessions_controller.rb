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
          session_token, refresh_token = SessionToken.generate_for(user:)
          track_session_token!(session_token)
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

        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "refresh_replaced")

        new_session_token, refresh_token = SessionToken.generate_for(user: session_token.user)
        track_session_token!(new_session_token)
        render json: Auth::SessionResponseBuilder.build(
          user: session_token.user,
          session_token: new_session_token,
          refresh_token: refresh_token,
          jwt_encoder: method(:encode_jwt)
        )
      end

      # GET /api/v1/logged_in
      # @summary Check whether the provided token is valid
      # Returns session and user context if the token is valid.
      # @response Session valid (200) [UserSession]
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
      # @response Session timing (200) [Hash{ session_expires_at: String, session_token_id: Integer, seconds_remaining: Integer }]
      # @response Unauthorized (401) [Error]
      def remaining
        render json: Auth::SessionResponseBuilder.session_data(@current_session_token)
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
        end

        render json: { status: "Logged out successfully" }, status: :ok
      end

      private

      def login_params
        raw = (params[:session].presence || params).permit(:email_address, :emailAddress, :password)
        raw.to_h.tap do |hash|
          hash["email_address"] ||= hash.delete("emailAddress")
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
        session = Auth::SessionResponseBuilder.session_data(session_token)

        {
          logged_in: true,
          user: Auth::SessionResponseBuilder.user_data(user, flags: flags),
          is_admin: flags[:is_admin],
          is_superuser: flags[:is_superuser],
          redirect_path: Auth::SessionResponseBuilder.redirect_path_for(user),
          session_token_id: session[:session_token_id],
          session_expires_at: session[:session_expires_at],
          seconds_remaining: session[:seconds_remaining],
          session: session
        }
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
