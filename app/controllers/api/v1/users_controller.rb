module Api
  module V1
    class UsersController < ApplicationController
      # POST /api/v1/users
      # @summary Register a new user account
      # @no_auth
      def create
        user = User.new(user_params)
        unless user.save
          return render json: { errors: user.errors.full_messages }, status: :unprocessable_content
        end

        session_token, refresh_token = SessionToken.generate_for(user: user)
        render json: Auth::SessionResponseBuilder.build(
          user: user,
          session_token: session_token,
          refresh_token: refresh_token,
          jwt_encoder: method(:encode_jwt)
        ), status: :created
      end

      private

      def user_params
        # The role is not permitted here, as it defaults to 'user' and should only be changed by an admin.
        (params[:user].presence || params).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
