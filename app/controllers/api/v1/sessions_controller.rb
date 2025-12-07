require "jwt"

module Api
  module V1
    class SessionsController < ApplicationController
      before_action :authenticate_request!, only: [ :logged_in?, :destroy, :remaining ]
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/login
      # @summary Log in and create a session
      # @no_auth
      def create
        user = User.find_by(email_address: login_params[:email_address])
        if user&.disabled?
          return render_error(code: :account_disabled, message: "User account disabled", status: :forbidden)
        end

        if user&.authenticate(login_params[:password])
          session_token, refresh_token = SessionToken.generate_for(user:)
          render json: build_session_response(user:, session_token:, refresh_token:)
        else
          render_error(code: :invalid_credentials, message: "Invalid credentials", status: :unauthorized)
        end
      end

      # @summary Refresh the current session using a refresh token
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
        render json: build_session_response(user: session_token.user, session_token: new_session_token, refresh_token: refresh_token)
      end

      # GET /api/v1/logged_in
      # @summary Check whether the provided token is valid
      def logged_in?
        if @current_user
          render json: build_logged_in_response(@current_user, @current_session_token)
        else
          render json: { logged_in: false }, status: :unauthorized
        end
      end

      # @summary Return remaining time for the current session token
      def remaining
        expires_at = @current_session_token.expires_at
        render json: {
          session_expires_at: expires_at.iso8601,
          session_token_id: @current_session_token.id,
          seconds_remaining: seconds_remaining_for(@current_session_token)
        }
      end

      # DELETE /api/v1/logout
      # @summary Log out and revoke the current session token
      def destroy
        if @current_session_token
          @current_session_token.revoke!
          SessionEventBroadcaster.session_invalidated(@current_session_token, reason: "logout")
        end

        render json: { status: "Logged out successfully" }, status: :ok
      end

      private

      def login_params
        params.require(:session).permit(:email_address, :password)
      end

      def refresh_params
        params.require(:session).permit(:refresh_token)
      end

      def build_session_response(user:, session_token:, refresh_token:)
        jwt_payload = {
          user_id: user.id,
          session_token_id: session_token.id,
          is_admin: user.admin? || user.superadmin?,
          is_superuser: user.superadmin?
        }

        {
          token: encode_jwt(jwt_payload, expires_at: session_token.expires_at),
          refresh_token: refresh_token,
          session: session_data(session_token),
          is_admin: user.admin? || user.superadmin?,
          is_superuser: user.superadmin?,
          redirect_path: redirect_path_for(user),
          user: user_data(user)
        }
      end

      def build_logged_in_response(user, session_token)
        {
          logged_in: true,
          user: user_data(user),
          is_admin: user.admin? || user.superadmin?,
          is_superuser: user.superadmin?,
          redirect_path: redirect_path_for(user),
          session_token_id: session_token.id,
          session_expires_at: session_token.expires_at.iso8601,
          seconds_remaining: seconds_remaining_for(session_token),
          session: session_data(session_token)
        }
      end

      def user_data(user)
        UserSerializer.new(user).as_json.merge(
          is_admin: user.admin? || user.superadmin?,
          is_superuser: user.superadmin?
        )
      end

      def session_data(session_token)
        {
          session_token_id: session_token.id,
          session_expires_at: session_token.expires_at.iso8601,
          seconds_remaining: seconds_remaining_for(session_token)
        }
      end

      def redirect_path_for(user)
        return "/admin/auctions" if user.superadmin?
        nil
      end

      def seconds_remaining_for(session_token)
        [ (session_token.expires_at - Time.current).to_i, 0 ].max
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end
