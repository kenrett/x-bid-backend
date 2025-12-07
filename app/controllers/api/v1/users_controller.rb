module Api
  module V1
    class UsersController < ApplicationController
      # POST /api/v1/users
      # @summary Register a new user account
      # @no_auth
      def create
        user = User.new(user_params)
        if user.save
          token = encode_jwt(user_id: user.id)
          user_payload = UserSerializer.new(user).as_json
          render json: { token:, user: user_payload }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def user_params
        # The role is not permitted here, as it defaults to 'user' and should only be changed by an admin.
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
