module Api
  module V1
    class UsersController < ApplicationController
      resource_description do
        short 'User registration'
      end

      api :POST, '/users', 'Register a new user'
      param :user, Hash, desc: 'User details', required: true do
        param :name, String, desc: 'Full name of the user', required: true
        param :email_address, String, desc: 'Email for login', required: true
        param :password, String, desc: 'User password', required: true
        param :password_confirmation, String, desc: 'Password confirmation', required: true
      end
      error code: 422, desc: 'Unprocessable Entity - validation errors'
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
    end
  end
end