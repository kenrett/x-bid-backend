require 'jwt'

module Api
  module V1
    class SessionsController < ApplicationController
      resource_description do
        short 'User sessions and authentication'
      end

      api :POST, '/login', 'Authenticate a user and receive a JWT'
      param :session, Hash, desc: 'Session credentials', required: true do
        param :email_address, String, desc: 'User email', required: true
        param :password, String, desc: 'User password', required: true
      end
      error code: 401, desc: 'Unauthorized - Invalid credentials'
      before_action :authenticate_request!, only: [:logged_in?]

      # POST /api/v1/login
      def create
        user = User.find_by(email_address: params[:session][:email_address])
        if user&.authenticate(params[:session][:password]) 
          token = encode_jwt(user_id: user.id)
          # Manually serialize the user to ensure camelCase keys, then build the final payload.
          user_payload = UserSerializer.new(user).as_json
          render json: { token:, user: user_payload }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      api :GET, '/logged_in', 'Check if the current user token is valid'
      description 'Requires a valid JWT in the Authorization header (Bearer <token>).'
      error code: 401, desc: 'Unauthorized - Token is missing, invalid, or expired'
      # GET /api/v1/logged_in
      def logged_in?
        # This action relies on an authentication method that decodes the token
        # from the Authorization header and sets @current_user.
        if @current_user
          user_payload = UserSerializer.new(@current_user).as_json
          render json: { logged_in: true, user: user_payload }
        else
          render json: { logged_in: false }, status: :unauthorized
        end
      end

      api :DELETE, '/logout', 'Log out a user'
      description 'This is a dummy endpoint. JWTs are stateless; logout is handled client-side by deleting the token.'
      # DELETE /api/v1/logout
      def destroy
        # TODO: Make sure JWT is deleted on the frontend
        render json: { status: 'Logged out successfully' }, status: :ok
      end
    
      private
    end
  end
end
