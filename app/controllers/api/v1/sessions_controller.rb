require "jwt"

module Api
  module V1
    class SessionsController < ApplicationController
      resource_description do
        short 'User sessions and authentication'
      end

      before_action :authenticate_request!, only: [:logged_in?, :destroy, :remaining]
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      api :POST, '/login', 'Authenticate a user and receive a JWT'
      param :session, Hash, desc: 'Session credentials', required: true do
        param :email_address, String, desc: 'User email', required: true
        param :password, String, desc: 'User password', required: true
      end
      error code: 401, desc: 'Unauthorized - Invalid credentials'

      # POST /api/v1/login
      def create
        user = User.find_by(email_address: login_params[:email_address])
        if user&.authenticate(login_params[:password])
          session_token, refresh_token = SessionToken.generate_for(user:)
          render json: build_session_response(user:, session_token:, refresh_token:)
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      api :POST, "/session/refresh", "Refresh a session using the issued refresh token"
      param :session, Hash, required: true do
        param :refresh_token, String, desc: "The refresh token returned at login", required: true
      end
      error code: 401, desc: "Unauthorized - Refresh token invalid or expired"
      def refresh
        session_token = SessionToken.find_active_by_raw_token(refresh_params[:refresh_token])
        return render json: { error: "Invalid or expired session" }, status: :unauthorized unless session_token

        session_token.revoke!
        SessionEventBroadcaster.session_invalidated(session_token, reason: "refresh_replaced")

        new_session_token, refresh_token = SessionToken.generate_for(user: session_token.user)
        render json: build_session_response(user: session_token.user, session_token: new_session_token, refresh_token: refresh_token)
      end

      api :GET, '/logged_in', 'Check if the current user token is valid'
      description 'Requires a valid JWT in the Authorization header (Bearer <token>).'
      error code: 401, desc: 'Unauthorized - Token is missing, invalid, or expired'
      # GET /api/v1/logged_in
      def logged_in?
        if @current_user
          user_payload = UserSerializer.new(@current_user).as_json
          render json: {
            logged_in: true,
            user: user_payload,
            is_admin: @current_user.admin? || @current_user.superadmin?,
            is_superuser: @current_user.superadmin?,
            session_token_id: @current_session_token.id,
            session_expires_at: @current_session_token.expires_at.iso8601,
            seconds_remaining: seconds_remaining_for(@current_session_token)
          }
        else
          render json: { logged_in: false }, status: :unauthorized
        end
      end

      api :GET, "/session/remaining", "Return the remaining session lifetime"
      description "Requires Authorization header. Can be polled by the client to display an accurate countdown."
      def remaining
        expires_at = @current_session_token.expires_at
        render json: {
          session_expires_at: expires_at.iso8601,
          session_token_id: @current_session_token.id,
          seconds_remaining: seconds_remaining_for(@current_session_token)
        }
      end

      api :DELETE, '/logout', 'Log out a user'
      description 'Revokes the active session token and notifies subscribers.'
      # DELETE /api/v1/logout
      def destroy
        if @current_session_token
          @current_session_token.revoke!
          SessionEventBroadcaster.session_invalidated(@current_session_token, reason: "logout")
        end

        render json: { status: 'Logged out successfully' }, status: :ok
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
          session_token_id: session_token.id,
          session_expires_at: session_token.expires_at.iso8601,
          user: UserSerializer.new(user).as_json.merge(
            is_admin: user.admin? || user.superadmin?,
            is_superuser: user.superadmin?
          )
        }
      end

      def seconds_remaining_for(session_token)
        [(session_token.expires_at - Time.current).to_i, 0].max
      end

      def handle_parameter_missing(exception)
        render json: { error: exception.message }, status: :bad_request
      end
    end
  end
end
