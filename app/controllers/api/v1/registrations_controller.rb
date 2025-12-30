module Api
  module V1
    class RegistrationsController < ApplicationController
      # POST /api/v1/signup
      # @summary Register a new user account and create a session (login-equivalent contract)
      # @no_auth
      def create
        user = User.new(user_params)
        unless user.save
          return render json: { errors: user.errors.full_messages }, status: :unprocessable_content
        end

        session_token, refresh_token = SessionToken.generate_for(user: user)
        render json: build_session_response(user: user, session_token: session_token, refresh_token: refresh_token), status: :ok
      end

      private

      def user_params
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end

      # Keep this in sync with Api::V1::SessionsController#build_session_response.
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
          session: session_data(session_token),
          is_admin: user.admin? || user.superadmin?,
          is_superuser: user.superadmin?,
          redirect_path: redirect_path_for(user),
          user: user_data(user)
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
    end
  end
end
