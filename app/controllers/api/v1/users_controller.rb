module Api
  module V1
    class UsersController < ApplicationController
      # POST /api/v1/users
      def create
        user = User.new(user_params)
        if user.save
          token = encode_jwt(user_id: user.id)
          render json: { token:, user: user.slice(:id, :email_address, :role, :name) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def user_params
        # The role is not permitted here, as it defaults to 'user' and should only be changed by an admin.
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end

      # It's recommended to move this method to ApplicationController to share it with SessionsController.
      def encode_jwt(payload)
        payload_with_exp = payload.merge(exp: 24.hours.from_now.to_i)
        JWT.encode(payload_with_exp, Rails.application.secret_key_base, 'HS256')
      end
    end
  end
end