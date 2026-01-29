module Api
  module V1
    class RegistrationsController < ApplicationController
      # POST /api/v1/signup
      # @summary Register a new user account and create a session (login-equivalent contract)
      # @request_body Signup payload (application/json) [!SignupRequest]
      # @response Session created (201) [UserSession]
      # @response Unprocessable content (422) [ValidationErrors]
      # @no_auth
      def create
        user = User.new(user_params)
        unless user.save
          return render_error(
            code: :validation_error,
            message: user.errors.full_messages.to_sentence,
            status: :unprocessable_content,
            field_errors: user.errors.messages
          )
        end

        session_token, refresh_token = SessionToken.generate_for(user: user)
        track_session_token!(session_token)
        set_cable_session_cookie(session_token)
        set_browser_session_cookie(session_token)
        response.set_header("X-Auth-Mode", "cookie")
        render json: Auth::SessionResponseBuilder.build(
          user: user,
          session_token: session_token,
          refresh_token: refresh_token,
          jwt_encoder: method(:encode_jwt)
        ), status: :created
      end

      private

      def user_params
        (params[:user].presence || params).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
